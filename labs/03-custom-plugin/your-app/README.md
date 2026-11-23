# OrderDesk API

OrderDesk is a Windows-hosted C# / .NET Framework 4.8 Web API 2 application for browsing products, placing single-product orders, and cancelling orders.

## Requirements

- Windows with the .NET Framework 4.8 runtime and Developer Pack.
- Visual Studio or Build Tools with MSBuild and the .NET desktop build tools.
- Access to NuGet for the packages listed in `src\OrderDesk.Legacy\packages.config`.

The application is a console executable using OWIN self-hosting. It does not require IIS or a database.

## Build and run

Run these PowerShell commands from this folder:

```powershell
.\scripts\Build-Legacy.ps1
.\src\OrderDesk.Legacy\bin\Debug\OrderDesk.Legacy.exe --url http://localhost:5088/
```

The build helper locates Visual Studio MSBuild and restores the project's packages. The service listens on localhost; use `--url` to select another local address.

In a second terminal, browse the catalog:

```powershell
Invoke-RestMethod -Uri http://localhost:5088/api/products
```

Place an order:

```powershell
Invoke-RestMethod -Method Post -Uri http://localhost:5088/api/orders `
    -ContentType application/json -Body '{"productId":1,"quantity":2}'
```

Read or cancel the returned order using `GET /api/orders/{id}` or `POST /api/orders/{id}/cancel`.

Stop the service with Ctrl+C. Product stock and orders are held in memory; restarting the process restores the initial catalog and clears orders.
