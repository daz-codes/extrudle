# One kind of spreadsheet import. Subclasses declare their columns and import
# one row at a time. The header row is matched loosely ("Sage account ref",
# "sage_account_ref" and "SAGE ACCOUNT REF" are the same), blank cells are
# left alone (an import never clears a field), and unknown columns are
# reported and ignored.
#
# preview runs the whole import in a transaction and rolls it back, so it's
# checked by the real validations; save keeps it only if every row is fine.
class Import::Base
  class RowError < StandardError; end

  Column = Data.define(:name, :label, :required, :aliases, :example, :hint)
  Result = Data.define(:line, :label, :action, :errors) do
    def ok? = errors.empty?
  end

  class_attribute :columns, instance_writer: false, default: []

  def self.column(name, label: nil, required: false, aliases: [], example: nil, hint: nil)
    self.columns = columns + [ Column.new(name.to_s, label || name.to_s.humanize, required, aliases.map { normalise(_1) }, example, hint) ]
  end

  def self.kind = Import::KINDS.key(name)
  def self.title = kind.humanize
  def self.description = ""

  # "Sage account ref" → "sage_account_ref", "Silicone %" → "silicone_pct"
  def self.normalise(header) = header.to_s.downcase.gsub("%", " pct ").gsub(/[^a-z0-9]+/, "_").delete_prefix("_").delete_suffix("_")

  def self.template_csv
    rows = [ template_headers, template_example ]
    rows.map { |row| row.map { |value| value.to_s.match?(/[",\n]/) ? "\"#{value.to_s.gsub('"', '""')}\"" : value.to_s }.join(",") }.join("\r\n") + "\r\n"
  end

  def self.template_headers = columns.map(&:label)
  def self.template_example = columns.map(&:example)

  attr_reader :problems, :warnings, :results

  def initialize(text)
    @problems = []
    @warnings = []
    @results = []
    rows = Import::CsvReader.parse(text)
    if rows.empty?
      @problems << "The file is empty"
    else
      read_header(rows.first)
      @rows = rows.drop(1)
      @problems << "There are no rows under the header" if @rows.empty?
    end
  rescue Import::CsvReader::MalformedError => e
    @problems << e.message
  end

  def preview = run(keep: false)
  def save = run(keep: true)

  def ok? = problems.empty? && results.all?(&:ok?)
  def row_count = @rows.to_a.size
  def counts = results.group_by(&:action).transform_values(&:size)

  private
    def run(keep:)
      @results = []
      return false if problems.any?

      ActiveRecord::Base.transaction do
        @results = @rows.each_with_index.map { |cells, index| process(values_for(cells), line: index + 2) }
        raise ActiveRecord::Rollback unless keep && @results.all?(&:ok?)
      end
      ok?
    end

    # Each row in its own savepoint, so a failed row leaves nothing half done.
    def process(values, line:)
      label, action = ActiveRecord::Base.transaction(requires_new: true) { import_row(values) }
      Result.new(line:, label:, action:, errors: [])
    rescue RowError => e
      Result.new(line:, label: values.values.first, action: :failed, errors: [ e.message ])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(line:, label: values.values.first, action: :failed, errors: e.record.errors.full_messages)
    rescue ArgumentError, ActiveRecord::RecordNotUnique => e
      Result.new(line:, label: values.values.first, action: :failed, errors: [ e.message ])
    end

    def read_header(header)
      @mapping = {}
      header.each_with_index do |cell, index|
        key = self.class.normalise(cell)
        next if key.empty?

        if (column = columns.detect { _1.name == key || _1.aliases.include?(key) || self.class.normalise(_1.label) == key })
          @mapping[index] = column.name
        elsif (name = extra_column(key))
          @mapping[index] = name
        else
          @warnings << "Column \"#{cell.strip}\" isn't used and will be ignored"
        end
      end
      columns.select(&:required).reject { @mapping.value?(_1.name) }.each do |column|
        @problems << "The \"#{column.label}\" column is missing"
      end
    end

    # Subclasses can accept columns beyond the declared ones (e.g. a rate per line).
    def extra_column(_key) = nil

    # { "name" => "Brightform" } for the non-blank cells of known columns.
    def values_for(cells)
      @mapping.each_with_object({}) do |(index, name), values|
        value = cells[index].to_s.strip
        values[name] = value unless value.empty?
      end
    end

    def require_value(values, name, label)
      values[name] || raise(RowError, "#{label} can't be blank")
    end

    def boolean(value, label)
      case value.to_s.strip.downcase
      when "yes", "y", "true", "1", "x" then true
      when "no", "n", "false", "0", "" then false
      else raise RowError, "#{label} must be Yes or No, not \"#{value}\""
      end
    end

    # "Max roll on side" → "max_roll_on_side", checked against the allowed values.
    def choice(value, allowed, label)
      key = self.class.normalise(value)
      return key if allowed.include?(key)

      raise RowError, "#{label} must be one of #{allowed.map(&:humanize).to_sentence(last_word_connector: " or ")}, not \"#{value}\""
    end

    def find_by_name(model, name, label)
      model.where("LOWER(name) = ?", name.downcase).first || raise(RowError, "There's no #{label} called \"#{name}\"")
    end

    def date(value, label)
      Date.strptime(value, value.include?("/") ? "%d/%m/%Y" : "%Y-%m-%d")
    rescue Date::Error
      raise RowError, "#{label} must be a date like 31/12/2026, not \"#{value}\""
    end

    # Saves a record found or built by name, saying whether it was created, updated or unchanged.
    def save_record(record, attributes)
      action = record.new_record? ? :created : :updated
      record.assign_attributes(attributes)
      action = :unchanged if action == :updated && !record.changed?
      record.save!
      action
    end
end
