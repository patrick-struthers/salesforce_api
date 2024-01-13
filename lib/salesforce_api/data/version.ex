defmodule SalesforceApi.Data.Version do
  @moduledoc """
  Functions for interacting with SalesForce API endpoints that provide version data.
  """
  import SalesforceApi.ReqHelpers
  alias SalesforceApi.OauthClient


  @api_version_path "services/data"

  @doc """
  Given an oauth client with a base request struct, will query the salesforce API
  endpoint to determine which api versions are available.
  """
  @spec(list_api_versions(oauth_client :: OauthClient.t()) :: {:ok, term}, {:error, term})
  def list_api_versions(%OauthClient{base_request: base_request}) do
    {_, response} =
      base_request
      |> Req.update(url: @api_version_path)
      |> Req.request()

    extract_body(response)
  end
  
  @doc """
  Given an oauth client with base request struct, will query the salesforce API
  and return the latest API version available.
  """
  @spec latest_api_version_path(oauth_client :: OauthClient.t()) ::
          {:ok, String.t()} | {:error, term}
  def latest_api_version_path(oauth_client = %OauthClient{}) do
    with {:ok, versions} <- list_api_versions(oauth_client),
         do: {:ok, latest_path_from_version_list(versions)}
  end

  defp latest_path_from_version_list(version_list) when is_list(version_list) do
    Enum.reduce(version_list, {0, ""}, fn %{"version" => n_vsn, "url" => n_pat}, acc = {vsn, _} ->
      n_vsn = String.to_float(n_vsn) |> trunc()

      if n_vsn > vsn do
        {n_vsn, n_pat}
      else
        acc
      end
    end)
    |> elem(1)
  end
end
