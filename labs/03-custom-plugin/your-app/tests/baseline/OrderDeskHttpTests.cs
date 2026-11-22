using System.Net;
using System.Text;
using System.Text.Json;
using Xunit;
using Xunit.Abstractions;

namespace OrderDesk.Baseline.Tests;

public sealed class OrderDeskHttpTests(ITestOutputHelper output)
{
    [Fact]
    public async Task SeededCatalogHasExactShapeAndDecimalPrices()
    {
        await using var host = await ExternalHost.StartAsync(output);
        await AssertCatalogAsync(host, 10, 10);
        using var missing = await host.Client.GetAsync("api/orders/1");
        await AssertErrorAsync(missing, HttpStatusCode.NotFound, "Order not found.");
    }

    [Fact]
    public async Task CreateReturns201LocationAndPersistsExactOrderAndStock()
    {
        await using var host = await ExternalHost.StartAsync(output);
        await CreateAsync(host, 1, 2, 1, 19.95m, 39.90m);
        await AssertStoredOrderAsync(host, 1, 1, 2, 19.95m, 39.90m, "placed");
        await AssertCatalogAsync(host, 8, 10);
    }

    [Fact]
    public async Task FractionalPriceTotalIsExactNumericDecimal()
    {
        await using var host = await ExternalHost.StartAsync(output);
        await CreateAsync(host, 2, 3, 1, 0.10m, 0.30m);
        await AssertStoredOrderAsync(host, 1, 2, 3, 0.10m, 0.30m, "placed");
        await AssertCatalogAsync(host, 10, 7);
    }

    [Fact]
    public async Task IntegerStringsAreAccepted()
    {
        await using var host = await ExternalHost.StartAsync(output);
        using var response = await PostAsync(host, """{"productId":"1","quantity":"2"}""");
        await AssertCreatedAsync(response, 1, 1, 2, 19.95m, 39.90m);
        await AssertStoredOrderAsync(host, 1, 1, 2, 19.95m, 39.90m, "placed");
        await AssertCatalogAsync(host, 8, 10);
    }

    [Fact]
    public async Task ClientSuppliedMoneyDoesNotOverrideCatalog()
    {
        await using var host = await ExternalHost.StartAsync(output);
        using var response = await PostAsync(host,
            """{"productId":1,"quantity":2,"unitPrice":0.01,"total":0.02}""");
        await AssertCreatedAsync(response, 1, 1, 2, 19.95m, 39.90m);
        await AssertStoredOrderAsync(host, 1, 1, 2, 19.95m, 39.90m, "placed");
        await AssertCatalogAsync(host, 8, 10);
    }

    // Only these safe IDs enter the report. Malformed/raw JSON never appears in a test name.
    [Theory]
    [InlineData("NullBody")]
    [InlineData("MalformedBody")]
    [InlineData("EmptyBody")]
    [InlineData("EmptyObject")]
    [InlineData("MissingProductId")]
    [InlineData("MissingQuantity")]
    [InlineData("ZeroProductId")]
    [InlineData("NegativeProductId")]
    [InlineData("ZeroQuantity")]
    [InlineData("NegativeQuantity")]
    [InlineData("NullProductId")]
    [InlineData("NullQuantity")]
    [InlineData("MinimumProductId")]
    [InlineData("MinimumQuantity")]
    [InlineData("MinimumProductIdString")]
    [InlineData("MinimumQuantityString")]
    [InlineData("ProductAboveMaximum")]
    [InlineData("ProductBelowMinimum")]
    [InlineData("QuantityAboveMaximum")]
    [InlineData("QuantityBelowMinimum")]
    [InlineData("ProductStringAboveMaximum")]
    [InlineData("ProductStringBelowMinimum")]
    [InlineData("QuantityStringAboveMaximum")]
    [InlineData("QuantityStringBelowMinimum")]
    public async Task InvalidOrdersReturn400WithoutChangingState(string scenario)
    {
        string body = scenario switch
        {
            "NullBody" => "null",
            "MalformedBody" => "{",
            "EmptyBody" => "",
            "EmptyObject" => "{}",
            "MissingProductId" => """{"quantity":1}""",
            "MissingQuantity" => """{"productId":1}""",
            "ZeroProductId" => """{"productId":0,"quantity":1}""",
            "NegativeProductId" => """{"productId":-1,"quantity":1}""",
            "ZeroQuantity" => """{"productId":1,"quantity":0}""",
            "NegativeQuantity" => """{"productId":1,"quantity":-1}""",
            "NullProductId" => """{"productId":null,"quantity":1}""",
            "NullQuantity" => """{"productId":1,"quantity":null}""",
            "MinimumProductId" => """{"productId":-2147483648,"quantity":1}""",
            "MinimumQuantity" => """{"productId":1,"quantity":-2147483648}""",
            "MinimumProductIdString" => """{"productId":"-2147483648","quantity":1}""",
            "MinimumQuantityString" => """{"productId":1,"quantity":"-2147483648"}""",
            "ProductAboveMaximum" => """{"productId":2147483648,"quantity":1}""",
            "ProductBelowMinimum" => """{"productId":-2147483649,"quantity":1}""",
            "QuantityAboveMaximum" => """{"productId":1,"quantity":2147483648}""",
            "QuantityBelowMinimum" => """{"productId":1,"quantity":-2147483649}""",
            "ProductStringAboveMaximum" => """{"productId":"2147483648","quantity":1}""",
            "ProductStringBelowMinimum" => """{"productId":"-2147483649","quantity":1}""",
            "QuantityStringAboveMaximum" => """{"productId":1,"quantity":"2147483648"}""",
            "QuantityStringBelowMinimum" => """{"productId":1,"quantity":"-2147483649"}""",
            _ => throw new ArgumentOutOfRangeException(nameof(scenario), scenario, "Unknown scenario ID.")
        };
        await using var host = await ExternalHost.StartAsync(output);
        await PrimeExistingOrderAsync(host);
        using var response = await PostAsync(host, body);
        await AssertErrorAsync(response, HttpStatusCode.BadRequest, "Invalid order.");
        await AssertRejectedRequestLeftStateIntactAsync(host);
    }

    [Theory]
    [InlineData(3, false)]
    [InlineData(int.MaxValue, false)]
    [InlineData(int.MaxValue, true)]
    public async Task PositiveUnknownProductReturns404WithoutChangingState(int productId, bool integerString)
    {
        await using var host = await ExternalHost.StartAsync(output);
        await PrimeExistingOrderAsync(host);
        string body = integerString
            ? JsonSerializer.Serialize(new { productId = productId.ToString(System.Globalization.CultureInfo.InvariantCulture), quantity = 1 })
            : JsonSerializer.Serialize(new { productId, quantity = 1 });
        using var response = await PostAsync(host, body);
        await AssertErrorAsync(response, HttpStatusCode.NotFound, "Product not found.");
        await AssertRejectedRequestLeftStateIntactAsync(host);
    }

    [Theory]
    [InlineData(9, 1)]
    [InlineData(10, 0)]
    public async Task StockAtOrBelowAvailableSucceedsAndNextExcessLeavesStateIntact(int quantity, int remaining)
    {
        await using var host = await ExternalHost.StartAsync(output);
        decimal total = quantity == 9 ? 179.55m : 199.50m;
        await CreateAsync(host, 1, quantity, 1, 19.95m, total);
        await AssertCatalogAsync(host, remaining, 10);
        using var rejected = await PostAsync(host,
            JsonSerializer.Serialize(new { productId = 1, quantity = remaining + 1 }));
        await AssertErrorAsync(rejected, HttpStatusCode.Conflict, "Insufficient stock.");
        await AssertCatalogAsync(host, remaining, 10);
        await AssertStoredOrderAsync(host, 1, 1, quantity, 19.95m, total, "placed");
        await CreateAsync(host, 2, 1, 2, 0.10m, 0.10m);
        await AssertCatalogAsync(host, remaining, 9);
    }

    [Theory]
    [InlineData(11, false)]
    [InlineData(int.MaxValue, false)]
    [InlineData(int.MaxValue, true)]
    public async Task InsufficientStockReturns409WithoutChangingState(int quantity, bool integerString)
    {
        await using var host = await ExternalHost.StartAsync(output);
        await PrimeExistingOrderAsync(host);
        string body = integerString
            ? JsonSerializer.Serialize(new { productId = 1, quantity = quantity.ToString(System.Globalization.CultureInfo.InvariantCulture) })
            : JsonSerializer.Serialize(new { productId = 1, quantity });
        using var response = await PostAsync(host, body);
        await AssertErrorAsync(response, HttpStatusCode.Conflict, "Insufficient stock.");
        await AssertRejectedRequestLeftStateIntactAsync(host);
    }

    [Theory]
    [InlineData("Read")]
    [InlineData("Cancel")]
    public async Task MissingOrderOperationsReturn404WithoutChangingState(string operation)
    {
        await using var host = await ExternalHost.StartAsync(output);
        await PrimeExistingOrderAsync(host);
        using var response = operation == "Read"
            ? await host.Client.GetAsync("api/orders/2")
            : await PostCancelAsync(host, 2);
        await AssertErrorAsync(response, HttpStatusCode.NotFound, "Order not found.");
        await AssertRejectedRequestLeftStateIntactAsync(host);
    }

    [Fact]
    public async Task CancelReturnsExactOrderAndRestoresStock()
    {
        await using var host = await ExternalHost.StartAsync(output);
        await CreateAsync(host, 1, 3, 1, 19.95m, 59.85m);
        await AssertCatalogAsync(host, 7, 10);
        await CancelAsync(host, 1, 1, 3, 19.95m, 59.85m);
        await AssertStoredOrderAsync(host, 1, 1, 3, 19.95m, 59.85m, "cancelled");
        await AssertCatalogAsync(host, 10, 10);
        await CreateAsync(host, 1, 10, 2, 19.95m, 199.50m);
        await AssertCatalogAsync(host, 0, 10);
    }

    [Fact]
    public async Task RepeatedCancellationDoesNotRestockTwice()
    {
        await using var host = await ExternalHost.StartAsync(output);
        await CreateAsync(host, 1, 2, 1, 19.95m, 39.90m);
        await AssertCatalogAsync(host, 8, 10);
        await CancelAsync(host, 1, 1, 2, 19.95m, 39.90m);
        await CancelAsync(host, 1, 1, 2, 19.95m, 39.90m);
        await AssertStoredOrderAsync(host, 1, 1, 2, 19.95m, 39.90m, "cancelled");
        await AssertCatalogAsync(host, 10, 10);
        using var rejected = await PostAsync(host, """{"productId":1,"quantity":11}""");
        await AssertErrorAsync(rejected, HttpStatusCode.Conflict, "Insufficient stock.");
        await AssertCatalogAsync(host, 10, 10);
        await AssertStoredOrderAsync(host, 1, 1, 2, 19.95m, 39.90m, "cancelled");
        await CreateAsync(host, 1, 10, 2, 19.95m, 199.50m);
        await AssertCatalogAsync(host, 0, 10);
    }

    [Fact]
    public async Task MultipleOrdersHaveSeparateIdentitiesAndState()
    {
        await using var host = await ExternalHost.StartAsync(output);
        await CreateAsync(host, 1, 2, 1, 19.95m, 39.90m);
        await CreateAsync(host, 1, 3, 2, 19.95m, 59.85m);
        await CreateAsync(host, 2, 3, 3, 0.10m, 0.30m);
        await AssertCatalogAsync(host, 5, 7);
        await AssertStoredOrderAsync(host, 1, 1, 2, 19.95m, 39.90m, "placed");
        await AssertStoredOrderAsync(host, 2, 1, 3, 19.95m, 59.85m, "placed");
        await AssertStoredOrderAsync(host, 3, 2, 3, 0.10m, 0.30m, "placed");
        await CancelAsync(host, 1, 1, 2, 19.95m, 39.90m);
        await AssertCatalogAsync(host, 7, 7);
        await AssertStoredOrderAsync(host, 1, 1, 2, 19.95m, 39.90m, "cancelled");
        await AssertStoredOrderAsync(host, 2, 1, 3, 19.95m, 59.85m, "placed");
        await AssertStoredOrderAsync(host, 3, 2, 3, 0.10m, 0.30m, "placed");
        await CancelAsync(host, 2, 1, 3, 19.95m, 59.85m);
        await AssertCatalogAsync(host, 10, 7);
        await AssertStoredOrderAsync(host, 1, 1, 2, 19.95m, 39.90m, "cancelled");
        await AssertStoredOrderAsync(host, 2, 1, 3, 19.95m, 59.85m, "cancelled");
        await AssertStoredOrderAsync(host, 3, 2, 3, 0.10m, 0.30m, "placed");
    }

    private static async Task PrimeExistingOrderAsync(ExternalHost host)
    {
        await CreateAsync(host, 2, 1, 1, 0.10m, 0.10m);
        await AssertCatalogAsync(host, 10, 9);
    }

    private static async Task AssertRejectedRequestLeftStateIntactAsync(ExternalHost host)
    {
        await AssertCatalogAsync(host, 10, 9);
        await AssertStoredOrderAsync(host, 1, 2, 1, 0.10m, 0.10m, "placed");
        using var missing = await host.Client.GetAsync("api/orders/2");
        await AssertErrorAsync(missing, HttpStatusCode.NotFound, "Order not found.");
        await CreateAsync(host, 1, 1, 2, 19.95m, 19.95m);
        await AssertCatalogAsync(host, 9, 9);
    }

    private static async Task<HttpResponseMessage> PostAsync(ExternalHost host, string body)
    {
        using var content = new StringContent(body, Encoding.UTF8, "application/json");
        return await host.Client.PostAsync("api/orders", content);
    }

    private static async Task<HttpResponseMessage> PostCancelAsync(ExternalHost host, int id)
    {
        using var content = new StringContent("", Encoding.UTF8, "application/json");
        return await host.Client.PostAsync($"api/orders/{id}/cancel", content);
    }

    private static async Task CreateAsync(ExternalHost host, int productId, int quantity, int id,
        decimal unitPrice, decimal total)
    {
        using var response = await PostAsync(host, JsonSerializer.Serialize(new { productId, quantity }));
        await AssertCreatedAsync(response, id, productId, quantity, unitPrice, total);
    }

    private static async Task AssertCreatedAsync(HttpResponseMessage response, int id, int productId,
        int quantity, decimal unitPrice, decimal total)
    {
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        using var body = await JsonAsync(response);
        AssertOrder(body.RootElement, id, productId, quantity, unitPrice, total, "placed");
        Uri location = Assert.IsType<Uri>(response.Headers.Location);
        // Both absolute and relative Location forms are allowed; the port is not the contract.
        Assert.Equal($"/api/orders/{id}", new Uri(new Uri("http://localhost/"), location).AbsolutePath);
    }

    private static async Task AssertStoredOrderAsync(ExternalHost host, int id, int productId,
        int quantity, decimal unitPrice, decimal total, string status)
    {
        using var response = await host.Client.GetAsync($"api/orders/{id}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = await JsonAsync(response);
        AssertOrder(body.RootElement, id, productId, quantity, unitPrice, total, status);
    }

    private static async Task CancelAsync(ExternalHost host, int id, int productId, int quantity,
        decimal unitPrice, decimal total)
    {
        using var response = await PostCancelAsync(host, id);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = await JsonAsync(response);
        AssertOrder(body.RootElement, id, productId, quantity, unitPrice, total, "cancelled");
    }

    private static async Task AssertCatalogAsync(ExternalHost host, int notebookStock, int pencilStock)
    {
        using var response = await host.Client.GetAsync("api/products");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = await JsonAsync(response);
        Assert.Equal(JsonValueKind.Array, body.RootElement.ValueKind);
        Assert.Equal(2, body.RootElement.GetArrayLength());
        AssertProduct(body.RootElement[0], 1, "Notebook", 19.95m, notebookStock);
        AssertProduct(body.RootElement[1], 2, "Pencil", 0.10m, pencilStock);
    }

    private static void AssertProduct(JsonElement product, int id, string name, decimal price, int stock)
    {
        AssertProperties(product, "id", "name", "price", "stock");
        Assert.Equal(id, product.GetProperty("id").GetInt32());
        Assert.Equal(name, product.GetProperty("name").GetString());
        AssertMoney(product.GetProperty("price"), price);
        Assert.Equal(stock, product.GetProperty("stock").GetInt32());
    }

    private static void AssertOrder(JsonElement order, int id, int productId, int quantity,
        decimal unitPrice, decimal total, string status)
    {
        AssertProperties(order, "id", "productId", "quantity", "unitPrice", "total", "status");
        Assert.Equal(id, order.GetProperty("id").GetInt32());
        Assert.Equal(productId, order.GetProperty("productId").GetInt32());
        Assert.Equal(quantity, order.GetProperty("quantity").GetInt32());
        AssertMoney(order.GetProperty("unitPrice"), unitPrice);
        AssertMoney(order.GetProperty("total"), total);
        Assert.Equal(status, order.GetProperty("status").GetString());
    }

    private static async Task AssertErrorAsync(HttpResponseMessage response, HttpStatusCode status, string message)
    {
        Assert.Equal(status, response.StatusCode);
        using var body = await JsonAsync(response);
        AssertProperties(body.RootElement, "message");
        Assert.Equal(message, body.RootElement.GetProperty("message").GetString());
    }

    private static Task<JsonDocument> JsonAsync(HttpResponseMessage response)
    {
        Assert.Equal("application/json", response.Content.Headers.ContentType?.MediaType);
        return ReadAsync();

        async Task<JsonDocument> ReadAsync() =>
            JsonDocument.Parse(await response.Content.ReadAsStringAsync());
    }

    private static void AssertProperties(JsonElement value, params string[] names)
    {
        Assert.Equal(JsonValueKind.Object, value.ValueKind);
        Assert.Equal(names.OrderBy(name => name, StringComparer.Ordinal),
            value.EnumerateObject().Select(property => property.Name).OrderBy(name => name, StringComparer.Ordinal));
    }

    private static void AssertMoney(JsonElement value, decimal expected)
    {
        Assert.Equal(JsonValueKind.Number, value.ValueKind);
        Assert.Equal(expected, value.GetDecimal());
    }
}
