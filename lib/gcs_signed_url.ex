defmodule GcsSignedUrl do
  @moduledoc """
  Create Signed URLs for Google Cloud Storage in Elixir
  """

  alias GcsSignedUrl.{Client, Crypto, SignBlob, StringToSign}

  @type sign_v2_opts :: [
          verb: String.t(),
          md5_digest: String.t(),
          content_type: String.t(),
          expires: integer()
        ]

  @type sign_v4_opts :: [
          verb: String.t(),
          headers: Keyword.t(),
          query_params: Keyword.t(),
          valid_from: DateTime.t(),
          expires: integer
        ]

  @doc """
  Generate V2 signed url.

  ## Examples

      iex> client = GcsSignedUrl.Client.load(%{private_key: "...", client_email: "..."})
      iex> GcsSignedUrl.generate(client, "my-bucket", "my-object.mp4", expires: 1503599316)
      "https://storage.googleapis.com/my-bucket/my-object.mp4?Expires=15..."

  """
  @spec generate(
          Client.t(),
          String.t(),
          String.t(),
          sign_v2_opts
        ) :: String.t()
  def generate(%Client{client_email: client_email} = client, bucket, filename, opts \\ []) do
    %StringToSign{string_to_sign: string_to_sign, url_template: url_template} =
      StringToSign.generate_v2(client_email, bucket, filename, opts)

    signature = Crypto.sign(string_to_sign, client) |> Base.encode64()
    String.replace(url_template, "#SIGNATURE#", signature)
  end

  @doc """
  Generate V4 signed url using a locally present private key of a Google service account.

  ## Examples

      iex> client = GcsSignedUrl.Client.load(%{private_key: "...", client_email: "..."})
      iex> GcsSignedUrl.generate(client, "my-bucket", "my-object.mp4", verb: "PUT", expires: 1800, headers: ["Content-Type": "application/json"])
      "https://storage.googleapis.com/my-bucket/my-object.mp4?X-Goog-Expires=1800..."

  """
  @spec generate_v4(Client.t(), String.t(), String.t()) :: String.t()
  @spec generate_v4(Client.t(), String.t(), String.t(), sign_v4_opts) :: String.t()
  def generate_v4(client, bucket, filename, opts \\ [])

  def generate_v4(%Client{client_email: client_email} = client, bucket, filename, opts) do
    %StringToSign{string_to_sign: string_to_sign, url_template: url_template} =
      StringToSign.generate_v4(client_email, bucket, filename, opts)

    signature = Crypto.sign(string_to_sign, client) |> Base.encode16() |> String.downcase()
    String.replace(url_template, "#SIGNATURE#", signature)
  end

  @doc """
  Generate V4 signed url using the Google IAM REST API with a OAuth2 token of a service account.

  ## Examples

      iex> oauth_config = %GcsSignedUrl.SignBlob.OAuthConfig{service_account: "...", access_token: "..."}
      iex> GcsSignedUrl.generate(oauth_config, "my-bucket", "my-object.mp4", verb: "PUT", expires: 1800, headers: ["Content-Type": "application/json"])
      {:ok, "https://storage.googleapis.com/my-bucket/my-object.mp4?X-Goog-Expires=1800..."}

  """
  @spec generate_v4(SignBlob.OAuthConfig.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  @spec generate_v4(SignBlob.OAuthConfig.t(), String.t(), String.t(), sign_v4_opts) ::
          {:ok, String.t()} | {:error, String.t()}
  def generate_v4(
        %SignBlob.OAuthConfig{service_account: service_account} = oauth_config,
        bucket,
        filename,
        opts
      ) do
    %StringToSign{string_to_sign: string_to_sign, url_template: url_template} =
      StringToSign.generate_v4(service_account, bucket, filename, opts)

    case Crypto.sign(string_to_sign, oauth_config) do
      {:ok, signature} ->
        signature
        |> Base.decode64!()
        |> Base.encode16()
        |> String.downcase()
        |> (&String.replace(url_template, "#SIGNATURE#", &1)).()

      error ->
        error
    end
  end

  @doc """
  Calculate future timestamp from given hour offset.

  ## Examples

      iex> 10 |> GcsUrlSigner.hours_after
      1503599316

  """
  def hours_after(hour) do
    DateTime.utc_now()
    |> DateTime.to_unix()
    |> Kernel.+(hour * 3600)
  end
end
