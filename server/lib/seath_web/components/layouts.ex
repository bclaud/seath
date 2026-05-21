defmodule SeathWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use SeathWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_page, :atom, default: :dashboard
  attr :review_count, :integer, default: 0

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex h-screen bg-gray-50">
      <%!-- Sidebar --%>
      <aside class="w-64 bg-gray-900 text-white flex flex-col shrink-0">
        <div class="p-6 border-b border-gray-700">
          <h1 class="text-xl font-bold tracking-tight">Seath</h1>
          <p class="text-sm text-gray-600 mt-1">Document Manager</p>
        </div>

        <nav class="flex-1 p-4 space-y-1">
          <.nav_item navigate="/" icon="hero-home" active={@current_page == :dashboard}>
            Dashboard
          </.nav_item>
          <.nav_item navigate="/upload" icon="hero-arrow-up-tray" active={@current_page == :upload}>
            Upload
          </.nav_item>
          <.nav_item navigate="/review" icon="hero-check-badge" active={@current_page == :review}>
            Review
            <span :if={@review_count > 0} class="ml-auto bg-yellow-500 text-white text-xs px-2 py-0.5 rounded-full">
              {@review_count}
            </span>
          </.nav_item>
          <.nav_item navigate="/chat" icon="hero-chat-bubble-left-right" active={@current_page == :chat}>
            Chat
          </.nav_item>
        </nav>

        <div class="p-4 border-t border-gray-700">
          <.nav_item navigate="/settings" icon="hero-cog-6-tooth" active={@current_page == :settings}>
            Settings
          </.nav_item>
          <.nav_item navigate="/dev/dashboard" icon="hero-chart-bar" active={false}>
            Admin
          </.nav_item>
        </div>
      </aside>

      <%!-- Main content --%>
      <main class="flex-1 overflow-y-auto">
        {render_slot(@inner_block)}
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end

  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  def nav_item(assigns) do
    ~H"""
    <a
      href={@navigate}
      class={[
        "flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors",
        if(@active, do: "bg-gray-700 text-white", else: "text-gray-300 hover:bg-gray-800 hover:text-white")
      ]}
    >
      <.icon name={@icon} class="w-5 h-5 shrink-0" />
      <span class="flex-1">{render_slot(@inner_block)}</span>
    </a>
    """
  end
end
