defmodule SalesforceApi.OauthClient do
  @moduledoc """
  Handles creation of OauthClients for the SalesForce API.
  """
  defstruct [
    :token_url,
    :client_id,
    :client_secret,
    :access_token,
    :environment,
    :base_request,
    :data_path,
    :sobject_path,
    :query_path,
    :query_size_limit,
    :base_uri
  ]

  alias SalesforceApi.AccessToken
  alias SalesforceApi.Data.Version
  alias SalesforceApi.Data.Sobjects

  @oauth_path "services/oauth2/token"
  @sobject_path "sobjects"
  @query_path "query"

  @type t :: %__MODULE__{
          token_url: String.t() | nil,
          client_id: String.t() | nil,
          client_secret: String.t() | nil,
          access_token: SalesforceApi.AccessToken.t() | nil,
          environment: atom | nil,
          base_request: Req.Request.t() | nil,
          data_path: String.t() | nil,
          sobject_path: String.t() | nil,
          query_path: String.t() | nil,
          query_size_limit: integer | nil,
          base_uri: String.t() | nil
        }
  @type base_uri :: String.t()
  @type client_id :: String.t()
  @type client_secret :: String.t()

  @doc """
  Creates a new oauth client struct without 
  fetching an API token or creating a base 
  request.
  """
  @spec new(base_uri, client_id, client_secret) :: t
  def new(base_uri, client_id, client_secret) do
    %__MODULE__{
      token_url: make_oauth_path(base_uri),
      client_id: client_id,
      client_secret: client_secret,
      base_uri: base_uri
    }
  end

  @doc """
  Creates a new oauth client with the api token loaded, and 
  a base request added to the struct. Will also set the data
  path to the latest availble version.

  This function can fail becasue it depends on interaction with the 
  SF API.
  """
  @spec new_with_base(base_uri, client_id, client_secret) :: {:ok, t} | {:error, term}
  def new_with_base(base_uri, client_id, client_secret) do
    with {:ok, struct} <- new_with_token(base_uri, client_id, client_secret),
         struct <- make_base_request(struct),
         {:ok, data_path} <- Version.latest_api_version_path(struct),
         struct <- add_data_path(struct, data_path),
         struct <- add_sobject_path(struct),
         struct <- add_query_path(struct),
         {:ok, query_size_limit} <- Sobjects.get_max_query_result_size(struct) do
      {:ok, %{struct | query_size_limit: query_size_limit}}
    end
  end

  defp add_data_path(client = %__MODULE__{}, dp), do: %{client | data_path: dp}

  defp add_sobject_path(client = %__MODULE__{data_path: dp}),
    do: Map.put(client, :sobject_path, Path.join([dp, @sobject_path]))

  defp add_query_path(client = %__MODULE__{data_path: dp}),
    do: Map.put(client, :query_path, Path.join([dp, @query_path]))

  @doc """
  Creates a new oauth client with the api token loaded.

  This function can fail becasue it depends on interaction with the 
  SF API.
  """
  @spec new_with_token(base_uri, client_id, client_secret) :: {:ok, t} | {:error, term}
  def new_with_token(base_uri, client_id, client_secret) do
    with struct <- new(base_uri, client_id, client_secret),
         {:ok, struct} <- fetch_token(struct) do
      {:ok, struct}
    end
  end

  @doc """
  Will add a base request to an Oauth client struct.
  The struct must have a token set.
  """
  @spec make_base_request(t) :: t
  def make_base_request(
        client = %__MODULE__{
          base_uri: base_uri,
          access_token: %AccessToken{access_token: token}
        }
      )
      when is_binary(token) do
    Map.put(
      client,
      :base_request,
      Req.new(
        base_url: base_uri,
        auth: {:bearer, token}
      )
    )
    |> IO.inspect(label: "with base request")
  end

  @doc """
  Adds API token to a Oauth clien struct.

  This function can fail becasue it depends on interaction with the 
  SF API.
  """
  @spec fetch_token(t) :: {:ok, t} | {:error, term}
  def fetch_token(
        %__MODULE__{
          token_url: token_url,
          client_id: client_id,
          client_secret: client_secret
        } = client_struct
      )
      when client_secret != nil and client_id != nil and client_secret != nil do
    with {:ok, resp} <- request_token(client_id, client_secret, token_url),
         body <- Map.get(resp, :body),
         {:ok, token} <- AccessToken.new(body) do
      {:ok, Map.put(client_struct, :access_token, token)}
    end
  end

  def fetch_token(_arg) do
    {:error, "invalid client"}
  end

  @doc """
  Requests an API token from the SF oauth endpoint.

  This function can fail becasue it depends on interaction with the 
  SF API.
  """
  @spec request_token(
          client_id :: String.t(),
          client_secret :: String.t(),
          token_url :: String.t()
        ) :: {:ok, map} | {:error, term}
  def request_token(client_id, client_secret, token_url) do
    Req.post(token_url,
      form: [
        grant_type: "client_credentials",
        client_id: client_id,
        client_secret: client_secret
      ]
    )
  end

  @spec make_oauth_path(String.t()) :: String.t()
  defp make_oauth_path(base_url) do
    Path.join([
      base_url,
      @oauth_path
    ])
  end
end
