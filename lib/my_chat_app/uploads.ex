defmodule MyChatApp.Uploads do
  @doc """
  Streams a local file to S3 and returns its public URL.
  Raises on failure.
  """
  def upload!(local_path, original_filename, content_type) do
    bucket = Application.fetch_env!(:my_chat_app, :s3_bucket)
    region = Application.get_env(:ex_aws, :region, "us-east-1")
    ext    = Path.extname(original_filename)
    key    = "chat/#{Ecto.UUID.generate()}#{ext}"

    local_path
    |> ExAws.S3.Upload.stream_file()
    |> ExAws.S3.upload(bucket, key,
      content_type: content_type,
      acl: :public_read
    )
    |> ExAws.request!()

    "https://#{bucket}.s3.#{region}.amazonaws.com/#{key}"
  end
end
