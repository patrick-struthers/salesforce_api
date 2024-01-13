defmodule SalesforceApiTest do
  use ExUnit.Case
  doctest SalesforceApi

  test "greets the world" do
    assert SalesforceApi.hello() == :world
  end
end
