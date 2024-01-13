defmodule SalesforceApi.AccessToken do
  defstruct [:access_token, :issued_at]

  @type t :: %__MODULE__{
          access_token: nil | String.t(),
          issued_at: nil | String.t()
        }

  @spec new(input_token :: map) :: {:ok, t} | {:error, String.t()}
  def new(%{"access_token" => access_token, "issued_at" => issued_at}) do
    {:ok,
     %__MODULE__{
       access_token: access_token,
       issued_at: issued_at
     }}
  end

  def new(_invalid_token) do
    {:error, "invlaid token response"}
  end
end
