# EventHorizon

EventHorizon is a lightweight, thread-safe package designed to build a clean and organized network communication layer in Swift. It uses async-await, the Sendable protocol, and generics for a type-safe and elegant API.

![EventHorizonSwiftiOSPackageHeaderImage](https://github.com/egzonpllana/EventHorizon/blob/main/event-horizon-header-image.png)
> The name **EventHorizon** represents the package's role as the ultimate control point for network requests. Just as an event horizon marks the boundary of a black hole, where nothing escapes its pull, this package captures, shapes, and directs network communication with precision. It ensures that every request and response passes through a structured and seamless pipeline, making network communication both reliable and efficient.

<p align="center">
    <img src="https://img.shields.io/badge/Swift-5.5%2B-orange">
    <img src="https://img.shields.io/badge/iOS-15.0%2B-blue">
    <img src="https://img.shields.io/badge/macOS-12.0%2B-blue">
    <img src="https://img.shields.io/badge/watchOS-8.0%2B-blue">
    <img src="https://img.shields.io/badge/tvOS-15.0%2B-blue">
</p>

## Changelog

| Version | Type | Highlights |
| --- | --- | --- |
| 3.0.0 | Major / breaking | `AuthTokenStoreProviding` gains `accessTokenExpiry` and `setAccessTokenExpiry(_:)` — existing conformers must implement both. `APIClient` adds `prepareRequest(_:)` for background-session uploads and a `tokenRefreshDepth` guard that prevents infinite recursion when a refreshed token is still rejected. Duplicate 401 logging is suppressed during a refresh retry. |
| 2.0.0 | Major | Introduces `AuthTokenStoreProviding`, `NetworkMonitorProtocol`, `NetworkAwareInterceptor`, and `TokenRefreshingInterceptorProtocol`. `APIClient`, `RetryInterceptor`, and task management received a substantial rewrite. |

#### Elegant and type-safe API
```swift
let posts: [PostDTO] = try await apiClient.request(APIEndpoint.getPosts)
```

## Features
💡 **Type-Safe API Calls** – Strongly typed networking built with Swift generics.  
⚡️ **Async/Await Execution** – Modern concurrency for structured asynchronous workflows.  
🧩 **Flexible Interceptors** – Global hooks for request and response customization.  
🔍 **Low-Level Access** – Full control over `URLSession` for advanced configurations.  
🚥 **Request Lifecycle** – Built-in task tracking for queuing, execution, and cancellation.  
🧾 **Environment-Aware Logging** – Configurable logging via `EHLoggerProtocol` for any environment. 

## Interceptors
EventHorizon includes a set of built-in interceptors, but you can create and inject your custom interceptors as needed.

- `AuthInterceptor` - Injects an authorization token into network requests.
- `LoggingInterceptor` - Logs request and response details for debugging.
- `RequestTimeoutInterceptor` - Configures custom timeout intervals for requests.
- `HeaderInjectorInterceptor` - Adds custom headers to outgoing requests.
- `RetryInterceptor` - Automatically retries failed requests based on status codes.

## Mocking and Tests Support
- [MockAPIClient](https://github.com/egzonpllana/EventHorizon/blob/main/Sources/EventHorizon/TestsSupport/Mocks/MockAPIClient.swift)
- [MockNetworkInterceptor](https://github.com/egzonpllana/EventHorizon/blob/main/Sources/EventHorizon/TestsSupport/Mocks/MockNetworkInterceptor.swift)
- [Package Unit Tests](https://github.com/egzonpllana/EventHorizon/tree/main/Tests/EventHorizonTests)
  
## Networking Layer - Data Flow
![EventHorizonSwiftiOSPackageDataFlowImage](https://github.com/egzonpllana/EventHorizon/blob/main/event-horizon-networking-data-flow.png)

### API Layer
- **Components**:
  - `APIEndpoint`: Defines API routes and configurations.
  - `APIClient`: Manages network requests and responses.
  - `Network Interceptor`: Handles request modifications (e.g., authentication, logging).
- **Role**: This layer abstracts networking details, ensuring maintainability and separation of concerns.
- **Flow**: The repository calls `APIEndpoint` → passes it to `APIClient` → processed through `Network Interceptor` before sending the request.

### URLSession
- **Role**: The final networking component that executes HTTP requests and retrieves responses.
- **Flow**: `APIClient` sends the request via `URLSession`, receives the response, and decodes it using `JSONDecoder`.

### Data Flow
1. **Repository interacts** with `APIEndpoint` and `APIClient`.
2. **Network Interceptor** modifies the request (if needed) before reaching `URLSession`.
3. **URLSession fetches** data from the remote server.
4. **Response data** is decoded and propagated back through the layers.

## Installation
To integrate EventHorizon into your project, add the following dependency to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/egzonpllana/EventHorizon", from: "1.0.0")
]
```

### Adding via Xcode
1. Open your Xcode project.
2. Go to **File** → **Add Package Dependencies..**.
3. Enter the URL: `https://github.com/egzonpllana/EventHorizon`.
4. Set the dependency rule to **Up to Next Major Version** (or choose your preferred versioning).
5. Click **Add Package** and select EventHorizon for your targets.


## Usage
1. Import the EventHorizon module into your Swift files.
2. Create an instance of `APIClient` and configure it with the desired interceptors.
3. Use the `APIClient` instance to perform network requests.

### Example
#### Create an APIClient instance with interceptors:
```swift
import EventHorizon

let apiClient = APIClient(
    interceptors: [
        // Inject any NetworkInterceptorProtocol
        LoggingInterceptor()
    ]
)
```

#### Make network requests using APIClient:
```swift
// Request with expected response type, e.g., [PostDTO]
// API: 
// func request<T: Decodable & Sendable>(_ endpoint: any APIEndpointProtocol) async throws -> T
let posts: [PostDTO] = try await apiClient.request(APIEndpoint.getPosts)

// Void request (e.g., POST)
// API:
// func request(_ endpoint: any APIEndpointProtocol) async throws
try await apiClient.request(APIEndpoint.createPost(newPost))

// Multi-part request with upload progress, e.g., image upload.
// API:
// @discardableResult func request(_ endpoint: any APIEndpointProtocol,
// progressDelegate: (any UploadProgressDelegateProtocol)?) async throws -> Data?
try await apiClient.request(
    APIEndpoint.uploadImage(...),
    progressDelegate: UploadProgressDelegateProtocol
)
```

### Unit Testing with MockAPIClient
You can use `MockAPIClient` to mock network requests while unit testing your `ViewModel`.

```swift
import XCTest
@testable import EventHorizon

final class MyViewModelTests: XCTestCase {
    var mockAPIClient: MockAPIClient!
    var viewModel: MyViewModel!

    override func setUp() async throws {
        mockAPIClient = MockAPIClient()
        viewModel = MyViewModel(apiClient: mockAPIClient)
    }

    func testFetchData_Success() async throws {
        let mockResponse = MockResponse(message: "Success", status: "OK")
        try mockAPIClient.setMockResponse(mockResponse, forPath: "/mock")
        
        try await viewModel.fetchData()
        
        XCTAssertEqual(viewModel.message, "Success")
    }

    func testFetchData_Failure() async throws {
        mockAPIClient.setShouldThrowError(true)
        
        do {
            try await viewModel.fetchData()
            XCTFail("Expected error but got success.")
        } catch {
            XCTAssertNotNil(error)
        }
    }
}
```

## Mocking URL Session
You can use a custom URL Session and Interceptors to inject into the APIClient.
```swift
let apiClient = APIClient(
    session: NetworkSessionProtocol, // Inject Mocked Session
    interceptors: [any NetworkInterceptor] // Inject Mocked Interceptors
)
```

### Real app example:
https://github.com/egzonpllana/NetworkLayerSwift6

### The meaning behind this package name EventHorizon
https://www.space.com/black-holes-event-horizon-explained.html

## License
EventHorizon is released under the MIT license. See LICENSE for details.

