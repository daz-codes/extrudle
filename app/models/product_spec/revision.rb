# Saves edits to a product spec, respecting "immutable once used":
#
# * Unused spec, or only `active` changed: update it in place.
# * Used spec (on an order): leave it untouched and save the changes as the
#   next revision of the same code. Line rates are copied, and the old revision
#   is deactivated so new orders pick the new one. Existing orders keep theirs.
#
#   revision = ProductSpec::Revision.new(spec, params)
#   if revision.save
#     redirect_to revision.spec   # the updated spec, or the new revision
#   else
#     render :edit                # errors are on the original spec
#   end
class ProductSpec::Revision
  IN_PLACE_ATTRIBUTES = %w[ active ].freeze

  attr_reader :original, :spec

  def initialize(spec, attributes)
    @original = spec
    @attributes = attributes
    @spec = spec
  end

  def save
    original.assign_attributes(@attributes)
    return false unless original.valid?

    if needs_new_revision?
      create_revision
    else
      original.save
    end
  end

  def revised?
    spec != original
  end

  private
    def needs_new_revision?
      original.used? && (original.changed - IN_PLACE_ATTRIBUTES).any?
    end

    def create_revision
      if original.code_changed?
        original.errors.add(:code, "can't change on a spec that's used on orders")
        return false
      end

      revision = ProductSpec.new(revision_attributes)

      ProductSpec.transaction do
        revision.save!
        revision.copy_line_rates_from(original)
        original.restore_attributes
        original.update!(active: false)
      end

      @spec = revision
      true
    rescue ActiveRecord::RecordInvalid => e
      e.record.errors.each { |error| original.errors.add(error.attribute, error.message) } if e.record != original
      false
    end

    def revision_attributes
      original.attributes
        .except("id", "created_at", "updated_at")
        .merge("revision" => original.next_revision, "active" => true)
    end
end
