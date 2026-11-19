module DispatchHelper
  def delivery_note_badge(note)
    if note.draft?
      tag.span("Draft", class: "badge badge-quiet")
    elsif note.exported?
      tag.span("Sent to Sage", class: "badge bg-ok-50 text-ok-700")
    else
      tag.span("Dispatched", class: "badge badge-lime")
    end
  end

  # "1–4, 7" from reel numbers.
  def reel_numbers_text(numbers)
    numbers.sort.slice_when { |a, b| b != a + 1 }.map { _1.size > 1 ? "#{_1.first}–#{_1.last}" : _1.first.to_s }.join(", ")
  end
end
