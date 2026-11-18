# Consistent, touch-sized form rows: label, input, hint and inline errors.
#
#   <%= form.text_row :name, hint: "As it appears on paperwork" %>
#   <%= form.select_row :currency, Currency::CODES %>
#   <%= form.radio_row :silicone, ProductSpec.silicones.keys %>
#   <%= form.check_row :active %>
class ExtrudleFormBuilder < ActionView::Helpers::FormBuilder
  INPUT = "field-input"
  INPUT_ERROR = "border-bad-600 focus:outline-bad-600"

  def error_summary
    return if object.nil? || object.errors.empty?

    @template.tag.div(role: "alert", class: "rounded-md border border-bad-600/30 bg-bad-50 px-4 py-3 text-bad-700") do
      @template.tag.p("Please fix the following:", class: "font-semibold") +
        @template.tag.ul(class: "mt-1 list-disc pl-5") do
          @template.safe_join(object.errors.full_messages.map { |m| @template.tag.li(m) })
        end
    end
  end

  %i[ text_field email_field telephone_field number_field ].each do |input|
    define_method(input.to_s.sub("_field", "_row")) do |method, label: nil, hint: nil, suffix: nil, wrapper: nil, **options|
      row(method, label:, hint:, wrapper:) do
        field = public_send(input, method, **input_options(method, options, hint))
        suffix ? with_suffix(field, suffix) : field
      end
    end
  end

  def text_area_row(method, label: nil, hint: nil, wrapper: nil, **options)
    row(method, label:, hint:, wrapper:) do
      text_area(method, **input_options(method, options.reverse_merge(rows: 3, class: "#{INPUT} py-2"), hint))
    end
  end

  def select_row(method, choices, label: nil, hint: nil, wrapper: nil, select_options: {}, **options)
    row(method, label:, hint:, wrapper:) { select(method, choices, select_options, **input_options(method, options, hint)) }
  end

  # Big tappable options, for enums with a handful of values.
  def radio_row(method, values, label: nil, hint: nil, labels: {}, wrapper: nil)
    @template.tag.fieldset(class: wrapper) do
      @template.tag.legend(label || humanize(method), class: "field-label") +
        @template.tag.div(class: "flex flex-wrap gap-2") do
          @template.safe_join(values.map { |value| radio_option(method, value, labels[value.to_s] || value.to_s.humanize) })
        end +
        footer(method, hint)
    end
  end

  def check_row(method, label: nil, hint: nil, wrapper: nil)
    @template.tag.div(class: wrapper) do
      @template.tag.label(class: "flex min-h-12 cursor-pointer items-center gap-3") do
        check_box(method, class: "size-5 accent-ink-900") +
          @template.tag.span(label || humanize(method), class: "font-semibold") +
          (hint ? @template.tag.span(hint, class: "text-sm text-ink-600") : "".html_safe)
      end + errors_for(method)
    end
  end

  private
    def row(method, label:, hint:, wrapper:)
      @template.tag.div(class: wrapper) do
        self.label(method, label || humanize(method), class: "field-label") + yield + footer(method, hint)
      end
    end

    def input_options(method, options, hint)
      classes = [ options.delete(:class) || INPUT ]
      classes << INPUT_ERROR if errors?(method)
      options.merge(class: classes.join(" "), aria: { invalid: errors?(method) || nil, describedby: describedby(method, hint) })
    end

    def with_suffix(field, suffix)
      @template.tag.div(class: "field-group") do
        field + @template.tag.span(suffix, class: "field-suffix")
      end
    end

    def radio_option(method, value, text)
      @template.tag.label(class: "choice") do
        radio_button(method, value, class: "size-5 accent-ink-900") + @template.tag.span(text)
      end
    end

    def footer(method, hint)
      (hint ? @template.tag.p(hint, id: hint_id(method), class: "field-hint") : "".html_safe) + errors_for(method)
    end

    def errors_for(method)
      return "".html_safe unless errors?(method)
      messages = error_keys(method).flat_map { |key| object.errors.full_messages_for(key) }
      @template.tag.p(messages.to_sentence, id: error_id(method), class: "mt-1 text-sm font-medium text-bad-700")
    end

    def errors?(method)
      object.respond_to?(:errors) && error_keys(method).any? { |key| object.errors.include?(key) }
    end

    # A supplier_id field also shows errors on the supplier association (e.g. "must exist").
    def error_keys(method)
      method = method.to_sym
      association = method.to_s.delete_suffix("_id").to_sym if method.end_with?("_id")
      [ method, association ].compact
    end

    def describedby(method, hint)
      ids = []
      ids << hint_id(method) if hint
      ids << error_id(method) if errors?(method)
      ids.join(" ").presence
    end

    def humanize(method)
      object.class.respond_to?(:human_attribute_name) ? object.class.human_attribute_name(method) : method.to_s.humanize
    end

    def hint_id(method) = "#{object_name}_#{method}_hint"
    def error_id(method) = "#{object_name}_#{method}_error"
end
