defmodule NFTMediaHandler do
  @moduledoc """
  Module resizes and uploads images to R2/S3 bucket.
  """

  require Logger
  alias NFTMediaHandler.Image.Resizer
  alias NFTMediaHandler.R2.Uploader

  @spec prepare_media_and_upload(binary() | File.Stream.t(), any()) :: map()
  def prepare_media_and_upload(file_path, file_name) do
    {:ok, image} = Image.open(file_path)

    thumbnails = Resizer.resize(file_path, image) |> dbg()

    uploaded_thumbnails =
      Enum.map(thumbnails, fn {size, image} ->
        with {:ok, _result, uploaded_file_url} <- Uploader.upload_image(image, generate_file_name(file_name, size)) do
          {size, uploaded_file_url}
        else
          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.into(%{})

    uploaded_original_url =
      with {:ok, binary} <- File.read(file_path),
           {:ok, _result, uploaded_file_url} <- Uploader.upload_image(binary, generate_file_name(file_name)) do
        uploaded_file_url
      else
        _ ->
          nil
      end

    max_size_or_original =
      uploaded_original_url ||
        (
          {_, url} =
            Enum.max_by(uploaded_thumbnails, fn {size, _} ->
              {int_size, _} = Integer.parse(size)
              int_size
            end)

          url
        )

    Enum.reduce(Resizer.sizes(), uploaded_thumbnails, fn {_, size}, acc ->
      if Map.has_key?(acc, size) do
        acc
      else
        Map.put(acc, size, max_size_or_original)
      end
    end)
    |> Map.put("original", uploaded_original_url)
  end

  defp generate_file_name(image_name, size \\ "original") do
    "#{image_name}_#{size}.jpg"
  end
end