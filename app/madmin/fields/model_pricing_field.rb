class ModelPricingField < Madmin::Field
  def formatted_summary(record)
    pricing = value(record)
    return "—" if pricing.blank?

    parts = []
    if (text = pricing.dig("text_tokens", "standard"))
      input = text["input_per_million"]
      output = text["output_per_million"]
      if input && output
        parts << "$#{format_price(input)}/$#{format_price(output)}"
      elsif input
        parts << "$#{format_price(input)} in"
      end
    end
    parts.empty? ? "—" : parts.join(" | ")
  end

  def format_price(val)
    return "0" if val.nil?
    val < 0.01 ? "%.4f" % val : "%.2f" % val
  end
end
