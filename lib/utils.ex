defmodule FraudChecker.Utils do
  def load_json_file_to_map(filename) do
    with {:ok, body} <- File.read(filename), {:ok, json} <- Jason.decode(body), do: {:ok, json}
  end

  def sanitize_string(str, chars_to_remove) do
    str
    |> String.downcase()
    |> String.trim()
    |> String.replace(chars_to_remove, "")
  end

  def strings_match?(left, right) do
    jaro = String.jaro_distance(left, right)
    jaro >= 0.8
  end
end
