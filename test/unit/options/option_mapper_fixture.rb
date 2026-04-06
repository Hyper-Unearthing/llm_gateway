# frozen_string_literal: true

module OptionMapperFixture
  module_function

  def superset_options
    {
      max_completion_tokens: 1234,
      cache_key: "abc",
      cache_retention: "long",
      reasoning: "high",
      temperature: 0.2,
      response_format: "json_object"
    }
  end
end
