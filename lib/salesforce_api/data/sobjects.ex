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
         do: {:ok, desc.body}
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

  ## Options
  - records: if set to all will retrieve all records.
  - file: if set results will be saved in JSON format to the 
  file path specified.
  - fields: if set to all the behavior of the function will change.
  The query string will be given an implicit SELECT predicate that 
  contains all the known fields for the table.
  """
  @spec make_soql_query(client :: OauthClient.t(), query_string :: String.t(), opts :: list) ::
          {:ok, term} | {:error, term} | :ok
  def make_soql_query(
        %OauthClient{base_request: request, query_path: qp} = client,
        query_string,
        opts \\ []
      )
      when request != nil and is_binary(qp) and is_binary(query_string) do
    opts = Keyword.merge([file: nil, records: nil], opts) |> Map.new()

    %{
      opts: opts,
      error: false,
      client: client,
      fetched: false,
      query_string: query_string
    }
    |> maybe_query_all()
    |> maybe_all_results()
    |> maybe_first_results()
    |> caller_feedback()
  end

  defp maybe_query_all(
        %{opts: %{fields: :all}, query_string: query_string, error: false, client: client} =
          process
      ) do
    case get_table_field_names(client, extract_table(query_string)) do
      {:error, error_message} ->
        process
        |> Map.put(:error, true)
        |> Map.put(:error_message, error_message)

      {:ok, fields} ->
        process
        |> Map.update!(:query_string, &add_select_clause_to_query(&1, fields))
    end
  end

  defp maybe_query_all(process), do: process

  defp maybe_all_results(
        %{
          opts: %{records: :all},
          fetched: false,
          query_string: query_string,
          error: false,
          client: client
        } = process
      ) do
    case make_soql_query_all(client, query_string) do
      {:ok, result} ->
        process
        |> Map.put(:fetched, true)
        |> Map.put(:results, result)
        |> IO.inspect(label: "results added")

      {:error, message} ->
        process
        |> Map.put(:fetched, true)
        |> Map.put(:error, true)
        |> Map.put(:error_message, message)
    end
  end

  defp maybe_all_results(process), do: process

  defp maybe_first_results(
        %{
          opts: %{records: nil},
          query_string: query_string,
          error: false,
          client: client,
          fetched: false
        } = process
      ) do
    case Req.get(client.base_request, url: client.query_path, params: [q: query_string]) do
      {:ok, result} ->
        process
        |> Map.put(:fetched, true)
        |> Map.put(:results, result.body["records"])

      {:error, message} ->
        process
        |> Map.put(:fetched, true)
        |> Map.put(:error, true)
        |> Map.put(:error_message, message)
    end
  end

  defp maybe_first_results(process), do: process

  defp maybe_record_results(
        %{opts: %{file_name: file_name}, fetched: false, results: results, error: false} = process
      )
      when not is_nil(file_name) do
    case File.write(file_name, Jason.decode!(results)) do
      :ok ->
        process

      {:error, error_message} ->
        process
        |> Map.put(:error, true)
        |> Map.put(:error_message, error_message)
    end
  end

  defp maybe_record_results(process), do: process

  defp caller_feedback(%{error: true, error_message: error_message}), do: {:error, error_message}

  defp caller_feedback(%{opts: %{file_name: file_name}}) when not is_nil(file_name),
    do: {:ok, "results written to #{file_name}"}

  defp caller_feedback(%{results: result}), do: {:ok, result}

  defp get_table_field_names(client, table_name) do
    with {:ok, description} <- describe_object(client, table_name) do
      description["fields"]
      |> Enum.map(& &1["name"])
      |> then(&{:ok, &1})
    end
  end

  defp extract_table(query_string) do
    query_string
    |> String.split(" ")
    |> Enum.drop_while(&(&1 != "FROM"))
    |> Enum.at(1)
  end

  defp field_names_to_clause(field_names) do
    "SELECT #{Enum.join(field_names, ",")}"
  end

  defp add_select_clause_to_query(query, fields) do
    "#{field_names_to_clause(fields)} #{query}"
  end

  @spec make_soql_query_all(client :: OauthClient.t(), query_string :: String.t()) ::
          {:ok, list} | {:error, term}
  defp make_soql_query_all(
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
        |> List.flatten()

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
