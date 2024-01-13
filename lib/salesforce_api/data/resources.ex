defmodule SalesforceApi.Data.Resources do
  @moduledoc """
  Functions for interacting with the rest API endpoints that return information about 
  available API endpoints.

  All functions assume that the base request and data url have been set on the client struct.
  """

  alias SalesforceApi.OauthClient
  import SalesforceApi.ReqHelpers

  @doc """
  Will request a list of all available API endpoints from the SalesForce API
  """
  @spec list_endpoints(OauthClient.t) :: {:ok, term} | {:error, term}
  def list_endpoints(%OauthClient{base_request: req, data_path: dp})
      when is_binary(dp) and req != nil do
      {_, response} = req
      |> Req.update(url: dp)
      |> Req.Request.run_request()

     extract_body(response) 
  end

end
