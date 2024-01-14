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

  Will only retrieve the first page of results for the query.
  """
  @spec make_soql_query(client :: OauthClient.t(), query_string :: String.t(), opts :: list) ::
          {:ok, term} | {:error, term} | :ok
  def make_soql_query(
        %OauthClient{base_request: request, query_path: qp} = client,
        query_string,
        opts \\ []
      )
      when request != nil and is_binary(qp) and is_binary(query_string) do
    opts = Keyword.merge([file: nil, all: false], opts)

    case {opts[:file], opts[:all]} do
      {nil, false} ->
        with {:ok, response} <- Req.get(request, url: qp, params: [q: query_string]),
             do: {:ok, response.body}

      {nil, true} ->
        make_soql_query_all(client, query_string)

      {file_name, false} ->
        with {:ok, response} <- Req.get(request, url: qp, params: [q: query_string]) do
          File.write(file_name, Jason.encode!(response.body))
        end

      {file_name, true} ->
        with {:ok, result} <- make_soql_query_all(client, query_string) do
          File.write(file_name, Jason.encode!(result))
        end
    end
  end

  @doc """
  Submits a soql query to the SF API endpoint and 
  retrieves all matching results.
  """
  @spec make_soql_query_all(client :: OauthClient.t(), query_string :: String.t()) ::
          {:ok, list} | {:error, term}
  def make_soql_query_all(
        %OauthClient{base_request: request, query_path: qp} = client,
        query_string
      )
      when request != nil and is_binary(qp) and is_binary(query_string) do
    with {:ok, init_body} <- make_soql_query(client, query_string) do
      results =
        init_body
        |> Stream.unfold(fn body ->
          # if there are more records the response body 
          # will have done set to false and a next_records
          # url will be present.
          case body do
            %{"done" => true, "records" => new_records} ->
              {new_records, :stop}

            %{"done" => false, "records" => new_records, "nextRecordsUrl" => next_record_url} ->
              {new_records, Req.get!(request, url: next_record_url).body}

            :stop ->
              nil

            invalid ->
              {{:error, invalid}, :stop}
          end
        end)
        |> Enum.to_list()

      case List.last(results) do
        {:error, message} ->
          {:error, %{message: message, fetched_before_error: Enum.drop(results, -1)}}

        _ ->
          {:ok, results}
      end
    end
  end

  defp extract_names(object_list) do
    Enum.map(object_list, fn %{"name" => name} -> name end)
  end
end
