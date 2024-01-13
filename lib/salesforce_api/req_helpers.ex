defmodule SalesforceApi.ReqHelpers do
  
  @doc """
  Extracts the body of a req request, if the status code was 
  not 200 an error tuple is returned.
  """ 
  @spec extract_body(Req.Response.t) :: {:ok, term} | {:error, term}
  def extract_body(resp = %Req.Response{status: 200}) do
    {:ok, resp.body}
  end

  def extract_body(resp = %Req.Response{}) do
    {:error, [status_code: resp.status, body: resp.body]}
  end
end
