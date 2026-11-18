module Currency
  CODES = Money::CURRENCIES.keys.freeze
  INCOTERMS = %w[ EXW FCA FAS FOB CFR CIF CPT CIP DAP DPU DDP ].freeze
end
