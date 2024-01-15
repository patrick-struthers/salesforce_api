defmodule SalesforceApi.ExecuteIf do
  defmacro match(value, match: match, function: function) do
    quote do
      if match?(unquote(match), unquote(value)) do
        unquote(function).(unquote(value))
      else
        unquote(value)
      end
    end
  end 

  defmacro match(value, match: match, when: when_clause, function: function) do
    quote do
      case unquote(value) do
        unquote(match) when unquote(when_clause) -> 
          unquote(function).(unquote(value))
        _ -> unquote(value)
      end
    end 
  end
end
