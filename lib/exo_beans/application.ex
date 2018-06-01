defmodule ExoBeans.Application do
  alias ExoBeans.Governer

  @moduledoc """
  the main application for exo beans
  """
  @doc false
  def start(_type, _args) do
    Governer.start_link(name: __MODULE__)
  end
end
