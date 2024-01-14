defmodule SalesforceApi.Data.Sobjects do
  @moduledoc """
  Functions for interacting with the salesforce objects API.  This endpoint
  is provides information on the business relevant data in salesforce.
  """

  alias SalesforceApi.OauthClient

  @doc """
  Retrieves a list of all available objects in the SF API that are **visible to your user**.   
  """
  @spec get_available_objects(client :: OauthClient.t()) :: {:ok, map} | {:error, term}
  def get_available_objects(%OauthClient{base_request: request, sobject_path: sop})
      when request != nil and is_binary(sop) do
    with {:ok, resp} <- Req.get(request, url: sop), do: {:ok, resp.body}
  end

  @doc """
  Retrieves a list containing the names of all available objects in the SF API that are **visible to your user**.
  """
  @spec get_object_names(client :: OauthClient.t()) :: {:ok, list} | {:error, term}
  def get_object_names(client = %OauthClient{base_request: request, sobject_path: sop})
      when request != nil and is_binary(sop) do
    case get_available_objects(client) do
      {:ok, body} ->
        body
        |> Map.get("sobjects")
        |> then(&{:ok, extract_names(&1)})

      error_tuple ->
        error_tuple
    end
  end

  @doc """
  Gets the maximum query result size configured for the SF tenant.
  """
  @spec get_max_query_result_size(client :: OauthClient.t()) :: {:ok, integer} | {:error, term}
  def get_max_query_result_size(client = %OauthClient{base_request: request, sobject_path: sop})
      when request != nil and is_binary(sop) do
    case get_available_objects(client) do
      {:ok, body} ->
        body
        |> Map.get("maxBatchSize")
        |> then(&{:ok, &1})

      error_tuple ->
        error_tuple
    end
  end

  @doc """
  Retrives the description of the given object from the SF API.
  """
  @spec describe_object(client :: OauthClient.t(), field_name :: String.t()) ::
          {:ok, map} | {:error, term}
  def describe_object(%OauthClient{base_request: request, sobject_path: sop}, field_name) do
    with {:ok, desc} <- Req.request(request, url: Path.join([sop, field_name, "describe"])),
         do: desc.body
  end

  @doc """
  Retrieves descriptions for all objects.
  """
  @spec describe_all_objects(client :: OauthClient.t()) :: {:ok, list} | {:error, term}
  def describe_all_objects(client = %OauthClient{}) do
    case get_object_names(client) do
      {:ok, names} ->
        for name <- names do
          describe_object(client, name)
        end

      error_tuple ->
        error_tuple
    end
  end

  @doc """
  Retrieves descriptions for all objects and saves them to a json at specified file path.
  """
  @spec create_field_descriptions(client :: OauthClient.t(), file_path :: String.t()) :: atom
  def create_field_descriptions(client = %OauthClient{}, file_path) do
    describe_all_objects(client)
    |> Jason.encode!()
    |> then(&File.write!(file_path, &1))
  end

  @doc """
  Submits a soql query to the SF API endpoint.
  """
  @spec make_soql_query(client :: OauthClient.t(), query_string :: String.t()) ::
          {:ok, map} | {:error, term}
  def make_soql_query(%OauthClient{base_request: request, query_path: qp}, query_string)
      when request != nil and is_binary(qp) and is_binary(query_string) do
    with {:ok, response} <- Req.get(request, url: qp, params: [q: query_string]),
         do: {:ok, response.body}
  end

  
  @doc """
  Submits a soql query to the SF API endpoint and 
  retrieves all matching results.
  """
  def make_soql_query(
        %OauthClient{base_request: request, query_path: qp} = client,
        query_string,
        :all
      )
      when request != nil and is_binary(qp) and is_binary(query_string) do
    get_all_records(client, fn client ->
      make_soql_query(client, query_string)
    end)
  end

  @doc """
  Fetches all records for a table.
  """
  def get_all_records(client = %OauthClient{}, fetch_function) do
    get_all_records(client, fetch_function, [])
  end

  def get_all_records(client, fetch_function, [])
      when is_function(fetch_function) do
    {:ok, res} = fetch_function.(client)

    case res do
      %{"done" => true, "records" => new_records} ->
        new_records

      %{"done" => false, "records" => new_records, "nextRecordsUrl" => next_record_url} ->
        get_all_records(client, next_record_url, new_records)

      _ ->
        raise("invalid response received from SF API: #{inspect(res)}")
    end
  end

  def get_all_records(client = %OauthClient{base_request: request}, records_url, records)
      when is_binary(records_url) do
    res = Req.get!(request, url: records_url)

    case res.body do
      %{"done" => true, "records" => new_records} ->
        new_records ++ records

      %{"done" => false, "records" => new_records, "nextRecordsUrl" => next_records_url} ->
        get_all_records(client, next_records_url, new_records ++ records)
    end
  end

  defp extract_names(object_list) do
    Enum.map(object_list, fn %{"name" => name} -> name end)
  end
end
