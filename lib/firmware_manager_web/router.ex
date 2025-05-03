defmodule FirmwareManagerWeb.Router do
  use FirmwareManagerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FirmwareManagerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FirmwareManagerWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/phoenix", EasterEggController, :phoenix
    
    live "/upgrade_logs", FirmwareManagerWeb.UpgradeLogLive.Index, :index
    live "/upgrade_logs/new", FirmwareManagerWeb.UpgradeLogLive.Index, :new
    live "/upgrade_logs/:id/edit", FirmwareManagerWeb.UpgradeLogLive.Index, :edit

    live "/upgrade_logs/:id", FirmwareManagerWeb.UpgradeLogLive.Show, :show
    live "/upgrade_logs/:id/show/edit", FirmwareManagerWeb.UpgradeLogLive.Show, :edit
  end

  # Other scopes may use custom stacks.
  # scope "/api", FirmwareManagerWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:firmware_manager, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FirmwareManagerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  if Application.compile_env(:firmware_manager, :dev_routes) do
    import AshAdmin.Router

    scope "/admin" do
      pipe_through :browser

      ash_admin "/"
    end
  end
end
