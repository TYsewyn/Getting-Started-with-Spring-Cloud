# Making Your Application More Resilient

## Table of Contents

* [Scaling Your Application](#scaling-your-application)
* [Load Balancing Your Upstream Traffic](#load-balancing-your-upstream-traffic)
    * [Configuring Our Shop Application](#configuring-our-shop-application)
    * [Adding New Dependencies to Our Gateway](#adding-new-dependencies-to-our-gateway)
    * [Configuring Security Inside Kubernetes](#configuring-security-inside-kubernetes)
    * [Configuring Our Load Balancer](#configuring-our-load-balancer)
    * [Adapting Our Route](#adapting-our-route)
    * [Deploying Our New Gateway](#deploying-our-new-gateway)
    * [Testing Our Route to an Unhealthy Instance](#testing-our-route-to-an-unhealthy-instance)
* [Respond Fast](#respond-fast)
    * [Configuring Our Shop Application](#configuring-our-shop-application-1)
    * [Testing Our Delay](#testing-our-delay)
    * [Adapting Our Route](#adapting-our-route-1)
    * [Deploying Our New Gateway](#deploying-our-new-gateway-1)
    * [Testing Our Route](#testing-our-route)
* [Rerouting Failing Traffic - Retry](#rerouting-failing-traffic---retry)
    * [Adapting Our Route](#adapting-our-route-2)
    * [Deploying Our New Gateway](#deploying-our-new-gateway-2)
    * [Testing Our Route](#testing-our-route-1)
* [Rerouting Failing Traffic - Circuit Breaker or Fallback](#rerouting-failing-traffic---circuit-breaker-or-fallback)
    * [Configuring Our Shop Application](#configuring-our-shop-application-2)
    * [Deploying Our New Shop](#deploying-our-new-shop)
    * [Testing Our Failing Shop](#testing-our-failing-shop)
    * [Adding Missing Dependencies](#adding-missing-dependencies)
    * [Adding Our New Load Balancer](#adding-our-new-load-balancer)
    * [Adapting Our Route](#adapting-our-route-3)
    * [Deploying Our New Gateway](#deploying-our-new-gateway-3)
    * [Testing Our Route](#testing-our-route-2)
* [Rate Limiting Incoming Traffic](#rate-limiting-incoming-traffic)
    * [Adding Missing Dependencies](#adding-missing-dependencies-1)
    * [Configuring Our Redis Connection](#configuring-our-redis-connection)
    * [Configuring Our Route](#configuring-our-route)

## Scaling Your Application

Because we do not want to have downtime we will scale our shop to two instances.
If one of them goes down we can still see the items we sell and, even more important, we can still accept orders!

```bash
$ kubectl scale deploy shop --replicas=2
```

Only after we see all the pods of our shop application in the `Running` state and the container for every pod is ready to accept traffic we can safely continue with the next step.

## Load Balancing Your Upstream Traffic

Because we are using the Kubernetes service as load balancer we do not have any possibility to adapt the way our traffic is being routed.
This is where our fourth Spring Cloud project comes into play: `Spring Cloud LoadBalancer`.
Using this project we have the ability and flexibility to load balance our requests from inside our gateway instance using code.
An example of a custom load balancer could be one which is based on the health of the upstream or target instance.
If the instance we want to send our request to is not healthy or down we temporarily ignore this one so we can send our requests to instances which can accept our requests.

### Configuring Our Shop Application

The health actuator endpoint uses a collection of `HealthIndicator`s where each of them indicate the health status, eg. your connection to a database or message broker.
For simulation purposes we will create our own `HealthIndicator` which will put our shop instance out of order.
Add a new `MaintenanceHealthIndicator.java` file to our shop application:

```java
package com.example.demo.shop;

import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.actuate.health.HealthIndicator;
import org.springframework.boot.actuate.health.Status;
import org.springframework.stereotype.Component;

@Component
public class MaintenanceHealthIndicator implements HealthIndicator {

	private Health health = Health.up().build();

	public void switchMode() {
		this.health = this.health.getStatus() == Status.OUT_OF_SERVICE ? Health.up().build() : Health.outOfService().build(); 
	}

	@Override
	public Health health() {
		return this.health;
	}

}
```

And a new `MaintenanceController.java` file:

```java
package com.example.demo.shop;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class MaintenanceController {

	public static final Logger logger = LoggerFactory.getLogger(MaintenanceController.class);

	private final MaintenanceHealthIndicator indicator;

	public MaintenanceController(MaintenanceHealthIndicator indicator) {
		this.indicator = indicator;
	}

	@PostMapping(value = "/maintenance")
	public ResponseEntity<Void> switchMode() {
		this.indicator.switchMode();
		logger.info("Switched to {}", this.indicator.health().getStatus());
		return ResponseEntity.ok().build();
	}

}
```

To get our new application on Kubernetes we need to create a new image, push the image to our registry and restart our gateway:

```bash
$ cd ~/demo/shop
$ ./mvnw spring-boot:build-image -Dspring-boot.build-image.imageName=localhost:5000/apps/shop
$ docker push localhost:5000/apps/shop
$ kubectl delete $(kubectl get pod --selector app=shop -o name)
```

### Adding New Dependencies to Our Gateway

For this to work we need to add two new dependency:

```xml
<dependency>
    <groupId>org.springframework.cloud</groupId>
    <artifactId>spring-cloud-starter-loadbalancer</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.cloud</groupId>
    <artifactId>spring-cloud-starter-kubernetes</artifactId>
</dependency>
```

At the core of Spring Cloud there is a discovery client abstraction.
Because we added the `spring-cloud-starter-kubernetes` dependency to our application we now have a specific Kubernetes-aware client that can discover all of our running instances.
This makes it much easier for us if and when we need to use another service registry system.
In the Spring Cloud Commons module there is also a `CompositeDiscoveryClient` implementation which allows you to connect to multiple service registry systems like Cloud Foundry, Hashicorp’s Consul or Apache Zookeeper.

### Configuring Security Inside Kubernetes

In case your Kubernetes cluster has more fine-grained role-based access control you need to make sure your application has the correct permissions to access the Kubernetes API.
In order for the service discovery to work we need to have the `get`, `list` and `watch` permissions for the `pods`, `services` and `endpoints` resources.
For this workshop we will create a `Role` named "namespace-reader" and give the default `ServiceAccount` the correct permissions.

```bash
$ kubectl create role namespace-reader --verb=get,list,watch --resource=pods,services,endpoints
$ kubectl create rolebinding default-account-namespace-reader --role=namespace-reader --serviceaccount=default:default
```

> NOTE: We suggest to create a specific `Role`, or `ClusterRole` in case you want to discover applications across namespaces, and a specific `ServiceAccount` for your application.

### Configuring Our Load Balancer

At the beginning of the load balancing section we mentioned a load balancer that can temporarily ignore application instances which are not healthy and thus unavailable.
To use both the service discovery and the health checks we will need to configure a custom `ServiceInstanceListSupplier`.
A `ServiceInstanceListSupplier` will be used by the load balancer to retrieve the list of available application instances and later on choose one from the list it received.
Update `GatewayApplication.java`:

```java
package com.example.demo.gateway;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.gateway.route.RouteLocator;
import org.springframework.cloud.gateway.route.builder.RouteLocatorBuilder;
import org.springframework.cloud.loadbalancer.annotation.LoadBalancerClient;
import org.springframework.cloud.loadbalancer.core.ServiceInstanceListSupplier;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Bean;

@SpringBootApplication
@LoadBalancerClient(name = "my-shop", configuration = GatewayApplication.LoadBalancerConfiguration.class)
public class GatewayApplication {

	public static void main(String[] args) {
		SpringApplication.run(GatewayApplication.class, args);
	}

	// snip

	public static final class LoadBalancerConfiguration {

		@Bean
		public ServiceInstanceListSupplier discoveryClientWithHealthChecksServiceInstanceListSupplier(
				ConfigurableApplicationContext context) {
			return ServiceInstanceListSupplier.builder()
						.withDiscoveryClient()
						.withHealthChecks()
						.build(context);
		}

	}

}
```

> NOTE: By default the `/actuator/health` path is used to determine the health of the running instance.
> Set `spring.cloud.loadbalancer.health-check.path.default` to change the default path which will be polled.
> To configure the path for a specific load balancer set `spring.cloud.loadbalancer.health-check.path.[SERVICE_ID]`.
> As an example, we should set the `spring.cloud.loadbalancer.health-check.path.my-shop` property.

### Adapting Our Route

To let our gateway know we want to use client side load balancing we need to adjust our route.
Instead of using `http://my-shop.default.svc.cluster.local` as the URI we only need to use the `lb` scheme and specify the name of the application, or when connecting to Kubernetes the name of the Kubernetes `Service`.
In your `application.yaml` file or Java config switch out `http://my-shop.default.svc.cluster.local` with `lb://my-shop`.

> NOTE: By default the load balancer client filter uses a blocking ribbon LoadBalancerClient under the hood.
> We suggest you use the non-blocking filter instead.
> You can switch to the non-blocking filter by setting the value of `spring.cloud.loadbalancer.ribbon.enabled` to `false`.

### Deploying Our New Gateway

To verify that our new configuration is working we need to create a new image, push the image to our registry and restart our gateway:

```bash
$ cd ~/demo/gateway
$ ./mvnw spring-boot:build-image -Dspring-boot.build-image.imageName=localhost:5000/apps/gateway
$ docker push localhost:5000/apps/gateway
$ kubectl delete $(kubectl get pod --selector app=gateway -o name)
$ pkill kubectl -9
$ kubectl port-forward services/my-gateway 8080:80 --address 0.0.0.0 > /dev/null 2>&1 &
```

If everything went well we should still see our list of items when executing:

```bash
$ http GET localhost:8080/catalog/items
```

### Testing Our Route to an Unhealthy Instance

Next we need to get one instance into maintenance mode:

```bash
$ kubectl port-forward $(kubectl get pod --selector app=shop -o name | head -n 1) 8081:8080 > /dev/null 2>&1 &
$ PID=$!
$ http GET localhost:8081/actuator/health
$ http POST localhost:8081/maintenance
$ http GET localhost:8081/actuator/health
$ kill -9 $PID
```

If we check the logs of the instance we just put out of order you should see the following line:

```bash
$ kubectl logs -f $(kubectl get pod --selector app=shop -o name | head -n 1)
```

> com.example.demo.MaintenanceController   : Switched to OUT_OF_SERVICE

If we open a new tab and browse to `<public DNS>:8080/catalog/items` we should not see any more logging being written to our console.
Press `Control+C` to stop following the logging.

> NOTE: It might be possible that you're still seeing some new logging.
> The load balancer will check the health status of the instances every 25 seconds by default.

## Respond Fast

Now that we made sure we only send our requests to healthy instances we are a little bit more relieved.
But what if our instance is healthy and the requests are taking a long time?
We do not want to let our customer wait a long time so we want to respond, or fail, fast.

### Configuring Our Shop Application

To simulate our misbehaving shop application we will first make some changes.
Add a `SimulationProperties.java`:

```java
package com.example.demo.shop;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "simulation")
public class SimulationProperties {

    private long delay = 0;

    public long getDelay() {
      return delay;
    }

    public void setDelay(long delay) {
      this.delay = delay;
    }
    
}
```

Update `ShopApplication.java`:

```java
package com.example.demo.shop;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;

@SpringBootApplication
@EnableConfigurationProperties({ SimulationProperties.class })
public class ShopApplication {

	public static void main(String[] args) {
		SpringApplication.run(ShopApplication.class, args);
	}

}
```

Update `CatalogController.java`:

```java
package com.example.demo.shop.catalog;

import com.example.demo.shop.SimulationProperties;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/catalog")
public class CatalogController {

    public static final Logger logger = LoggerFactory.getLogger(CatalogController.class);

    private final SimulationProperties simulationProperties;

    public CatalogController(SimulationProperties simulationProperties) {
        this.simulationProperties = simulationProperties;
    }

    @GetMapping(value = "/items", produces = { "application/json" })
    public ResponseEntity<String> retrieveAllItems() throws InterruptedException {
        Thread.sleep(this.simulationProperties.getDelay());
        logger.info("Received request for catalog items");
        return ResponseEntity.ok().body("[{ \"id\": \"6b76148d-0fda-4ebf-8966-d91bfaeb0236\", \"img\": \"https://images.unsplash.com/photo-1590688178590-bb8370b70528\", \"name\": \"Breakfast with homemade bread\", \"price\": 16 }, { \"id\": \"52d59380-79da-49d5-9d09-9716e20ccbc4\", \"img\": \"https://images.unsplash.com/photo-1592894869086-f828b161e90a\", \"name\": \"Brisket\", \"price\": 24 }, { \"id\": \"a7be01f8-b76e-4384-bf1d-e69d7bdbe4b4\", \"img\": \"https://images.unsplash.com/photo-1544025162-d76694265947\", \"name\": \"Pork Ribs\", \"price\": 20 }]");
    }
    
}
```

Update `BaseTestClass.java`:

```java
package com.example.demo.shop;

import org.junit.jupiter.api.BeforeEach;

import io.restassured.module.mockmvc.RestAssuredMockMvc;
import com.example.demo.shop.catalog.CatalogController;
import com.example.demo.shop.orders.OrdersController;

public class BaseTestClass {

    @BeforeEach
    public void setup() {
        RestAssuredMockMvc.standaloneSetup(new CatalogController(new SimulationProperties()), new OrdersController());
    }
    
}
```

And add the following lines to `application.properties`:

```properties
management.endpoints.web.exposure.include=env,health,info,refresh
management.endpoint.env.post.enabled=true
```

To get our changes on Kubernetes we need to create a new image, push the image to our registry and restart our gateway:

```bash
$ cd ~/demo/shop
$ ./mvnw spring-boot:build-image -Dspring-boot.build-image.imageName=localhost:5000/apps/shop
$ docker push localhost:5000/apps/shop
$ kubectl delete $(kubectl get pod --selector app=shop -o name)
```

### Testing Our Delay

Next we need to set the delay for one of our instances:

```bash
$ kubectl port-forward $(kubectl get pod --selector app=shop -o name | head -n 1) 8081:8080 > /dev/null 2>&1 &
$ PID=$!
$ http -v POST localhost:8081/actuator/env name=simulation.delay value:=120000
$ http -v POST localhost:8081/actuator/refresh
$ http -v GET localhost:8081/catalog/items --timeout 5
$ kill -9 $PID
```

We should see the following message, confirming our delay is correctly set:
> http: error: Request timed out (5.0s).

### Adapting Our Route

To configure our timeouts we need to adjust our route to our shop application in our gateway.

Adjust `GatewayApplication.java`:

```java
package com.example.demo.gateway;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.gateway.route.RouteLocator;
import org.springframework.cloud.gateway.route.builder.RouteLocatorBuilder;
import org.springframework.cloud.loadbalancer.annotation.LoadBalancerClient;
import org.springframework.cloud.loadbalancer.core.ServiceInstanceListSupplier;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Bean;

import static org.springframework.cloud.gateway.support.RouteMetadataUtils.CONNECT_TIMEOUT_ATTR;
import static org.springframework.cloud.gateway.support.RouteMetadataUtils.RESPONSE_TIMEOUT_ATTR;

@SpringBootApplication
@LoadBalancerClient(name = "my-shop", configuration = GatewayApplication.LoadBalancerConfiguration.class)
public class GatewayApplication {

	public static void main(String[] args) {
		SpringApplication.run(GatewayApplication.class, args);
	}

	@Bean
	public RouteLocator routes(RouteLocatorBuilder builder) {
		return builder.routes()
			.route("catalog_route",
				r -> r.path("/catalog/{*segment}")
				.uri("lb://my-shop")
				.metadata(RESPONSE_TIMEOUT_ATTR, 200)
				.metadata(CONNECT_TIMEOUT_ATTR, 200)
			)
			.route("orders_route",
				r -> r.path("/orders/{*segment}")
				.uri("lb://my-shop")
			)
		.build();
	}

	public static final class LoadBalancerConfiguration {

		@Bean
		public ServiceInstanceListSupplier discoveryClientWithHealthChecksServiceInstanceListSupplier(
				ConfigurableApplicationContext context) {
			return ServiceInstanceListSupplier.builder()
						.withDiscoveryClient()
						.withHealthChecks()
						.build(context);
		}

	}

}
```

Or update `application.yaml`:

```yaml
spring:
  cloud:
    gateway:
      routes:
      - id: catalog_route
        uri: lb://my-shop
        predicates:
        - Path=/catalog/{*segment}
        metadata:
          response-timeout: 200
          connect-timeout: 200
      - id: orders_route
        uri: lb://my-shop
        predicates:
        - Path=/orders/{*segment}
```

### Deploying Our New Gateway

To verify that our new configuration is working we need to create a new image, push the image to our registry and restart our gateway:

```bash
$ cd ~/demo/gateway
$ ./mvnw spring-boot:build-image -Dspring-boot.build-image.imageName=localhost:5000/apps/gateway
$ docker push localhost:5000/apps/gateway
$ kubectl delete $(kubectl get pod --selector app=gateway -o name)
$ pkill kubectl -9
$ kubectl port-forward services/my-gateway 8080:80 --address 0.0.0.0 > /dev/null 2>&1 &
```

### Testing Our Route

Now if we want to get our list we should see some weird behaviour happening:
Execute until you get a `504 Gateway Timeout` error:

```bash
$ http GET localhost:8080/catalog/items
```

## Rerouting Failing Traffic - Retry

We are now able to quickly send a response to our customer.
But what now?
We know our other instance is just working as expected.
Could we just send our request again to that other instance?

### Adapting Our Route

To configure a retry for a failing request we need to adjust our route to our shop application in our gateway.

> NOTE: Keep in mind that, ideally, you only want to retry idempotent requests.
> An HTTP method is idempotent if an identical request can be made once or several times in a row with the same effect while leaving the server in the same state.
> In other words, an idempotent method should not have any side-effects (except for keeping statistics).

Adjust `GatewayApplication.java`:

```java
package com.example.demo.gateway;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.gateway.route.RouteLocator;
import org.springframework.cloud.gateway.route.builder.RouteLocatorBuilder;
import org.springframework.cloud.loadbalancer.annotation.LoadBalancerClient;
import org.springframework.cloud.loadbalancer.core.ServiceInstanceListSupplier;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.http.HttpMethod;

import static org.springframework.cloud.gateway.support.RouteMetadataUtils.CONNECT_TIMEOUT_ATTR;
import static org.springframework.cloud.gateway.support.RouteMetadataUtils.RESPONSE_TIMEOUT_ATTR;

@SpringBootApplication
@LoadBalancerClient(name = "my-shop", configuration = GatewayApplication.LoadBalancerConfiguration.class)
public class GatewayApplication {

	public static void main(String[] args) {
		SpringApplication.run(GatewayApplication.class, args);
	}

	@Bean
	public RouteLocator routes(RouteLocatorBuilder builder) {
		return builder.routes()
			.route("catalog_route",
				r -> r.path("/catalog/{*segment}")
				.filters(f ->
					f.retry(c ->
						c.setRetries(2)
						.setMethods(HttpMethod.HEAD, HttpMethod.GET, HttpMethod.PUT, HttpMethod.DELETE)
					)
				)
				.uri("lb://my-shop")
				.metadata(RESPONSE_TIMEOUT_ATTR, 200)
				.metadata(CONNECT_TIMEOUT_ATTR, 200)
			)
			.route("orders_route",
				r -> r.path("/orders/{*segment}")
				.uri("lb://my-shop")
			)
		.build();
	}

	public static final class LoadBalancerConfiguration {

		@Bean
		public ServiceInstanceListSupplier discoveryClientWithHealthChecksServiceInstanceListSupplier(
				ConfigurableApplicationContext context) {
			return ServiceInstanceListSupplier.builder()
						.withDiscoveryClient()
						.withHealthChecks()
						.build(context);
		}

	}

}
```

Or update `application.yaml`:

```yaml
spring:
  cloud:
    gateway:
      routes:
      - id: catalog_route
        uri: lb://my-shop
        predicates:
        - Path=/catalog/{*segment}
        filters:
        - name: Retry
          args:
            retries: 2
            methods: HEAD,GET,PUT,DELETE
        metadata:
          response-timeout: 200
          connect-timeout: 200
      - id: orders_route
        uri: lb://my-shop
        predicates:
        - Path=/orders/{*segment}
```

### Deploying Our New Gateway

To verify that our new configuration is working we need to create a new image, push the image to our registry and restart our gateway:

```bash
$ cd ~/demo/gateway
$ ./mvnw spring-boot:build-image -Dspring-boot.build-image.imageName=localhost:5000/apps/gateway
$ docker push localhost:5000/apps/gateway
$ kubectl delete $(kubectl get pod --selector app=gateway -o name)
$ pkill kubectl -9
$ kubectl port-forward services/my-gateway 8080:80 --address 0.0.0.0 > /dev/null 2>&1 &
```

### Testing Our Route

If everything went well we should not see any errors and our list of items being returned in a couple of milliseconds.
To verify this, execute:

```bash
$ seq 10 | xargs -I INDEX http GET localhost:8080/catalog/items
```

## Rerouting Failing Traffic - Circuit Breaker or Fallback

Now that we've rerouted our request to our healthy instance we are back in business.
But what would happen if none of them could handle the request?
For example, we just deployed a second shop application with its own Kubernetes `Service` and updated our route in our gateway but we see there's something wrong with this new deployment.

### Configuring Our Shop Application

To simulate our misbehaving shop application we will need to make some changes again.
Update `SimulationProperties.java`:

```java
package com.example.demo.shop;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "simulation")
public class SimulationProperties {

    private long delay = 0;
	private boolean simulateErrors = false;

    public long getDelay() {
      return delay;
    }

    public void setDelay(long delay) {
      this.delay = delay;
    }

    public boolean getSimulateErrors() {
      return simulateErrors;
    }

    public void setSimulateErrors(boolean simulateErrors) {
      this.simulateErrors = simulateErrors;
    }

    public boolean simulateErrors() {
      return simulateErrors;
    }
    
}
```

And adjust `CatalogController.java`:

```java
package com.example.demo.shop.catalog;

import com.example.demo.shop.SimulationProperties;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/catalog")
public class CatalogController {

    public static final Logger logger = LoggerFactory.getLogger(CatalogController.class);

    private final SimulationProperties simulationProperties;

    public CatalogController(SimulationProperties simulationProperties) {
        this.simulationProperties = simulationProperties;
    }

    @GetMapping(value = "/items", produces = { "application/json" })
    public ResponseEntity<String> retrieveAllItems() throws InterruptedException {
        if (this.simulationProperties.simulateErrors()) {
            throw new RuntimeException("Oops!");
        }
        Thread.sleep(this.simulationProperties.getDelay());
        logger.info("Received request for catalog items");
        return ResponseEntity.ok().body("[{ \"id\": \"6b76148d-0fda-4ebf-8966-d91bfaeb0236\", \"img\": \"https://images.unsplash.com/photo-1590688178590-bb8370b70528\", \"name\": \"Breakfast with homemade bread\", \"price\": 16 }, { \"id\": \"52d59380-79da-49d5-9d09-9716e20ccbc4\", \"img\": \"https://images.unsplash.com/photo-1592894869086-f828b161e90a\", \"name\": \"Brisket\", \"price\": 24 }, { \"id\": \"a7be01f8-b76e-4384-bf1d-e69d7bdbe4b4\", \"img\": \"https://images.unsplash.com/photo-1544025162-d76694265947\", \"name\": \"Pork Ribs\", \"price\": 20 }]");
    }
    
}
```

### Deploying Our New Shop

To make sure we have a second version of our application we will also change the name of our image.
Execute the following commands to deploy the new shop:

```bash
$ cd ~/demo/shop/
$ ./mvnw spring-boot:build-image -Dspring-boot.build-image.imageName=localhost:5000/apps/shop-v2
$ docker push localhost:5000/apps/shop-v2
$ kubectl create deployment shop-v2 --image localhost:5000/apps/shop-v2
$ kubectl patch deployment shop-v2 --type json -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env", "value":[{"name":"SIMULATION_SIMULATE_ERRORS", "value": "true"}]}, {"op": "add", "path": "/spec/template/spec/containers/0/ports", "value":[{"containerPort":8080}]}]'
$ kubectl expose deployment shop-v2 --name my-shop-v2 --port 80 --target-port 8080
```

### Testing Our Failing Shop

To quickly check if the new version is indeed failing as intended execute:

```bash
$ kubectl port-forward $(kubectl get pod --selector app=shop-v2 -o name | head -n 1) 8081:8080 > /dev/null 2>&1 &
$ PID=$!
$ http GET localhost:8081/catalog/items
$ kill -9 $PID
```

### Adding Missing Dependencies

To make use of the circuit breaker pattern we need to add a new dependency.
Open your `pom.xml` file and add the following snippet to your dependencies:

```xml
<dependency>
	<groupId>org.springframework.cloud</groupId>
	<artifactId>spring-cloud-starter-circuitbreaker-reactor-resilience4j</artifactId>
</dependency>
```

### Adding Our New Load Balancer

Because we need to use a new service we also need to define this in our gateway.
To make our lives easier we are going to reuse the same configuration.

Update `GatewayApplication.java`:

```java
package com.example.demo.gateway;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.gateway.route.RouteLocator;
import org.springframework.cloud.gateway.route.builder.RouteLocatorBuilder;
import org.springframework.cloud.loadbalancer.annotation.LoadBalancerClient;
import org.springframework.cloud.loadbalancer.annotation.LoadBalancerClients;
import org.springframework.cloud.loadbalancer.core.ServiceInstanceListSupplier;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.http.HttpMethod;

import static org.springframework.cloud.gateway.support.RouteMetadataUtils.CONNECT_TIMEOUT_ATTR;
import static org.springframework.cloud.gateway.support.RouteMetadataUtils.RESPONSE_TIMEOUT_ATTR;

@SpringBootApplication
@LoadBalancerClients(value = {
	@LoadBalancerClient(name = "my-shop"),
	@LoadBalancerClient(name = "my-shop-v2")
}, defaultConfiguration = GatewayApplication.LoadBalancerConfiguration.class)
public class GatewayApplication {

	public static void main(String[] args) {
		SpringApplication.run(GatewayApplication.class, args);
	}

	// snip

	public static final class LoadBalancerConfiguration {

		@Bean
		public ServiceInstanceListSupplier discoveryClientWithHealthChecksServiceInstanceListSupplier(
				ConfigurableApplicationContext context) {
			return ServiceInstanceListSupplier.builder()
						.withDiscoveryClient()
						.withHealthChecks()
						.build(context);
		}

	}

}
```

### Adapting Our Route

Next we will send our requests to our new version but we will keep the previous configuration as a fallback.
For this to work we need to do a couple of things:
- Add a `/catalog_items_fallback` endpoint to the gateway which will make the request to `lb://my-shop/catalog/items`.
- Add the new route `catalog_items_route` which sends traffic to `lb://my-shop-v2` when a request matches `GET /catalog/items`.
- Add a circuit breaker to `catalog_items_route` which forwards traffic to `/catalog_items_fallback`.

Add `CatalogFallbackController.java`:

```java
package com.example.demo.gateway;

import java.time.Duration;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClient.Builder;

import reactor.core.publisher.Mono;

@RestController
public class CatalogFallbackController {

    private static final Logger logger = LoggerFactory.getLogger(CatalogFallbackController.class);

    private final WebClient.Builder webClientBuilder;

    public CatalogFallbackController(Builder webClientBuilder) {
        this.webClientBuilder = webClientBuilder;
    }

    @GetMapping("/catalog_items_fallback")
    public Mono<ResponseEntity<String>> getCatalogItemsFromV1() {
        logger.info("Retrieving catalog items from v1");
        return webClientBuilder.build().get().uri("http://my-shop/catalog/items").exchange()
        .timeout(Duration.ofMillis(200)).retry(2) // Just like in our route configuration, we want to have a fast response !
        .flatMap(cr -> cr.toEntity(String.class))
        .switchIfEmpty(Mono.just(ResponseEntity.notFound().build()));
    }
    
}
```

Adjust `GatewayApplication.java`:

```java
package com.example.demo.gateway;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.gateway.route.RouteLocator;
import org.springframework.cloud.gateway.route.builder.RouteLocatorBuilder;
import org.springframework.cloud.loadbalancer.annotation.LoadBalancerClient;
import org.springframework.cloud.loadbalancer.annotation.LoadBalancerClients;
import org.springframework.cloud.loadbalancer.core.ServiceInstanceListSupplier;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.http.HttpMethod;

import static org.springframework.cloud.gateway.support.RouteMetadataUtils.CONNECT_TIMEOUT_ATTR;
import static org.springframework.cloud.gateway.support.RouteMetadataUtils.RESPONSE_TIMEOUT_ATTR;

import java.util.Set;

@SpringBootApplication
@LoadBalancerClients(value = {
	@LoadBalancerClient(name = "my-shop"),
	@LoadBalancerClient(name = "my-shop-v2")
}, defaultConfiguration = GatewayApplication.LoadBalancerConfiguration.class)
public class GatewayApplication {

	public static void main(String[] args) {
		SpringApplication.run(GatewayApplication.class, args);
	}

	@Bean
	public RouteLocator routes(RouteLocatorBuilder builder) {
		return builder.routes()
			.route("catalog_items_route",
				r -> r.path("/catalog/items")
				.and().method(HttpMethod.GET)
				.filters(f ->
					f.circuitBreaker(c ->
						c.setFallbackUri("forward:/catalog_items_fallback")
						 .setStatusCodes(Set.of("500"))
					)
				)
				.uri("lb://my-shop-v2")
			)
			.route("catalog_route",
				r -> r.path("/catalog/{*segment}")
				.filters(f ->
					f.retry(c ->
						c.setRetries(2)
						.setMethods(HttpMethod.HEAD, HttpMethod.GET, HttpMethod.PUT, HttpMethod.DELETE)
					)
				)
				.uri("lb://my-shop")
				.metadata(RESPONSE_TIMEOUT_ATTR, 200)
				.metadata(CONNECT_TIMEOUT_ATTR, 200)
			)
			.route("orders_route",
				r -> r.path("/orders/{*segment}")
				.uri("lb://my-shop")
			)
		.build();
	}

	public static final class LoadBalancerConfiguration {

		@Bean
		public ServiceInstanceListSupplier discoveryClientWithHealthChecksServiceInstanceListSupplier(
				ConfigurableApplicationContext context) {
			return ServiceInstanceListSupplier.builder()
						.withDiscoveryClient()
						.withHealthChecks()
						.build(context);
		}

	}

}
```

Or update `application.yaml`:

```yaml
spring:
  cloud:
    gateway:
      routes:
      - id: catalog_items_route
        uri: lb://my-shop-v2
        predicates:
        - Path=/catalog/items
        - Method=GET
        filters:
        - name: CircuitBreaker
          args:
            fallbackUri: forward:/catalog_items_fallback
            statusCodes:
            - 500
      - id: catalog_route
        uri: lb://my-shop
        predicates:
        - Path=/catalog/{*segment}
        filters:
        - name: Retry
          args:
            retries: 2
            methods: HEAD,GET,PUT,DELETE
        metadata:
          response-timeout: 200
          connect-timeout: 200
      - id: orders_route
        uri: lb://my-shop
        predicates:
        - Path=/orders/{*segment}
```

### Deploying Our New Gateway

To verify that our new configuration is working we need to create a new image, push the image to our registry and restart our gateway:

```bash
$ cd ~/demo/gateway
$ ./mvnw spring-boot:build-image -Dspring-boot.build-image.imageName=localhost:5000/apps/gateway
$ docker push localhost:5000/apps/gateway
$ kubectl delete $(kubectl get pod --selector app=gateway -o name)
$ pkill kubectl -9
$ kubectl port-forward services/my-gateway 8080:80 --address 0.0.0.0 > /dev/null 2>&1 &
```

### Testing Our Route

If we check the logs of the gateway instance, open a new tab and browse to `<public DNS>:8080/catalog/items` you should see the following line:

```bash
$ kubectl logs -f $(kubectl get pod --selector app=gateway -o name | head -n 1)
```

> c.e.d.gateway.CatalogFallbackController  : Retrieving catalog items from v1

Press `Control+C` to stop following the logging.

## Rate Limiting Incoming Traffic

Suppose this is the first version of our API and that it doesn't have authentication or authorization.
Along comes this hacker who wants to hurt us by sending a huge amount of requests to our application.
One of the first things we can do is to add a rate limiter to our API gateway so that the requests of the hacker are not being sent to our application anymore.

### Adding Missing Dependencies

To keep track of all the used requests we will make use of Redis as our backing store.
This requires the use of the `spring-boot-starter-data-redis-reactive` Spring Boot starter.
Open your `pom.xml` file and add the following snippet to your dependencies:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-redis-reactive</artifactId>
</dependency>
```

### Configuring Our Redis Connection

Next we need to let our application know where our Redis instance is located.
If you followed the steps as outlined in [Setting up the environment](#setting-up-the-environment) you can use `redis.default.svc.cluster.local` as host.

```yaml
spring:
  redis:
    host: redis.default.svc.cluster.local
    password: Opstree@1234
```

### Configuring Our Route

The Redis implementation is based off of work done at [Stripe](https://stripe.com/blog/rate-limiters).
The algorithm used is the [Token Bucket Algorithm](https://en.wikipedia.org/wiki/Token_bucket).

We will set up our rate limiter using a custom `KeyResolver` implementation and three properties: `redis-rate-limiter.replenishRate`, `redis-rate-limiter.burstCapacity` and `redis-rate-limiter.requestedTokens`.

* The `KeyResolver` interface is used to group requests.
The default implementation of `KeyResolver` is the `PrincipalNameKeyResolver`, which retrieves the `Principal` from the `ServerWebExchange` and calls `Principal.getName()`.

* The `redis-rate-limiter.replenishRate` property is how many requests per second you want a user to be allowed to do, without any dropped requests.
This is the rate at which the token bucket is filled.

* The `redis-rate-limiter.burstCapacity` property is the maximum number of requests a user is allowed to do in a single second.
This is the number of tokens the token bucket can hold. Setting this value to zero blocks all requests.

* The `redis-rate-limiter.requestedTokens` property is how many tokens a request costs.
This is the number of tokens taken from the bucket for each request and defaults to 1.

In this example we will allow 1 request per second for every user.
While investigating the requests we saw our hacker is using a specific HTTP header called `X-HACK-TOOL`.
Since we have no authentication yet we will use this header to group our requests.

First we need to add our custom `KeyResolver` in `GatewayApplication.java`:

```java
package com.example.demo.gateway;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.gateway.filter.ratelimit.KeyResolver;
import org.springframework.cloud.loadbalancer.annotation.LoadBalancerClient;
import org.springframework.cloud.loadbalancer.annotation.LoadBalancerClients;
import org.springframework.cloud.loadbalancer.core.ServiceInstanceListSupplier;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Bean;

import reactor.core.publisher.Mono;

@SpringBootApplication
@LoadBalancerClients(value = {
	@LoadBalancerClient(name = "my-shop"),
	@LoadBalancerClient(name = "my-shop-v2")
}, defaultConfiguration = GatewayApplication.LoadBalancerConfiguration.class)
public class GatewayApplication {

	public static void main(String[] args) {
		SpringApplication.run(GatewayApplication.class, args);
	}

	// snip

	@Bean
	public KeyResolver userKeyResolver() {
		return exchange -> Mono.justOrEmpty(exchange.getRequest().getHeaders().getFirst("X-HACK-TOOL"));
	}

	public static final class LoadBalancerConfiguration {

		@Bean
		public ServiceInstanceListSupplier discoveryClientWithHealthChecksServiceInstanceListSupplier(
				ConfigurableApplicationContext context) {
			return ServiceInstanceListSupplier.builder()
						.withDiscoveryClient()
						.withHealthChecks()
						.build(context);
		}

	}
}
```

By default, if the `KeyResolver` does not find a key, requests are denied.
You can either adjust your custom `KeyResolver` to provide a default value which will group all requests together as if they were executed by the same person.
Or you can adjust this behavior by setting the `spring.cloud.gateway.filter.request-rate-limiter.deny-empty-key` (`true` or `false`) and `spring.cloud.gateway.filter.request-rate-limiter.empty-key-status-code` properties.

In this example we don't want to deny traffic which does not have this header.
Add `spring.cloud.gateway.filter.request-rate-limiter.deny-empty-key=false` to your configuration before continuing.

After we've configured our custom `KeyResolver` and our property we need to add a filter to our route.

Adjust `GatewayApplication.java`:

```java
package com.example.demo.gateway;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.gateway.filter.ratelimit.KeyResolver;
import org.springframework.cloud.gateway.filter.ratelimit.RedisRateLimiter;
import org.springframework.cloud.gateway.route.RouteLocator;
import org.springframework.cloud.gateway.route.builder.RouteLocatorBuilder;
import org.springframework.cloud.loadbalancer.annotation.LoadBalancerClient;
import org.springframework.cloud.loadbalancer.annotation.LoadBalancerClients;
import org.springframework.cloud.loadbalancer.core.ServiceInstanceListSupplier;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.http.HttpMethod;
import reactor.core.publisher.Mono;

import static org.springframework.cloud.gateway.support.RouteMetadataUtils.CONNECT_TIMEOUT_ATTR;
import static org.springframework.cloud.gateway.support.RouteMetadataUtils.RESPONSE_TIMEOUT_ATTR;

import java.util.Set;

@SpringBootApplication
@LoadBalancerClients(value = {
	@LoadBalancerClient(name = "my-shop"),
	@LoadBalancerClient(name = "my-shop-v2")
}, defaultConfiguration = GatewayApplication.LoadBalancerConfiguration.class)
public class GatewayApplication {

	public static void main(String[] args) {
		SpringApplication.run(GatewayApplication.class, args);
	}

	@Bean
	public RouteLocator routes(RouteLocatorBuilder builder) {
		return builder.routes()
			.route("catalog_items_route",
				r -> r.path("/catalog/items")
				.and().method(HttpMethod.GET)
				.filters(f ->
					f.requestRateLimiter()
						.rateLimiter(RedisRateLimiter.class,
							rl -> rl.setReplenishRate(1).setBurstCapacity(60).setRequestedTokens(1)
						)
					.and()
					.circuitBreaker(c ->
						c.setFallbackUri("forward:/catalog_items_fallback")
						 .setStatusCodes(Set.of("500"))
					)
				)
				.uri("lb://my-shop-v2")
			)
			.route("catalog_route",
				r -> r.path("/catalog/{*segment}")
				.filters(f ->
					f.requestRateLimiter()
						.rateLimiter(RedisRateLimiter.class,
							rl -> rl.setReplenishRate(1).setBurstCapacity(60).setRequestedTokens(1)
						)
					.and()
					.retry(c ->
						c.setRetries(2)
						.setMethods(HttpMethod.HEAD, HttpMethod.GET, HttpMethod.PUT, HttpMethod.DELETE)
					)
				)
				.uri("lb://my-shop")
				.metadata(RESPONSE_TIMEOUT_ATTR, 200)
				.metadata(CONNECT_TIMEOUT_ATTR, 200)
			)
			.route("orders_route",
				r -> r.path("/orders/{*segment}")
				.uri("lb://my-shop")
			)
		.build();
	}

	@Bean
	public KeyResolver userKeyResolver() {
		return exchange -> Mono.justOrEmpty(exchange.getRequest().getHeaders().getFirst("X-HACK-TOOL"));
	}

	public static final class LoadBalancerConfiguration {

		@Bean
		public ServiceInstanceListSupplier discoveryClientWithHealthChecksServiceInstanceListSupplier(
				ConfigurableApplicationContext context) {
			return ServiceInstanceListSupplier.builder()
						.withDiscoveryClient()
						.withHealthChecks()
						.build(context);
		}

	}

}
```

Or update `application.yaml`:

```yaml
spring:
  cloud:
    gateway:
      routes:
      - id: catalog_items_route
        uri: lb://my-shop-v2
        predicates:
        - Path=/catalog/items
        - Method=GET
        filters:
        - name: RequestRateLimiter
          args:
            redis-rate-limiter.replenishRate: 1
            redis-rate-limiter.burstCapacity: 60
            redis-rate-limiter.requestedTokens: 1
            key-resolver: "#{@userKeyResolver}"
        - name: CircuitBreaker
          args:
            fallbackUri: forward:/catalog_items_fallback
            statusCodes:
            - 500
      - id: catalog_route
        uri: lb://my-shop
        predicates:
        - Path=/catalog/{*segment}
        filters:
        - name: RequestRateLimiter
          args:
            redis-rate-limiter.replenishRate: 1
            redis-rate-limiter.burstCapacity: 60
            redis-rate-limiter.requestedTokens: 1
            key-resolver: "#{@userKeyResolver}"
        - name: Retry
          args:
            retries: 2
            methods: HEAD,GET,PUT,DELETE
        metadata:
          response-timeout: 200
          connect-timeout: 200
      - id: orders_route
        uri: lb://my-shop
        predicates:
        - Path=/orders/{*segment}
```

> NOTE: You can also define a rate limiter as a bean that implements the `RateLimiter` interface.
> In configuration you can reference the bean by name using SpEL in the `rate-limiter` property, eg. `rate-limiter: "#{@myRateLimiter}"` where `myRateLimiter` is the name of the bean.
> You can then remove the `redis-rate-limiter.replenishRate`, `redis-rate-limiter.burstCapacity` and `redis-rate-limiter.requestedTokens` properties.

### Testing Our Route

To verify that our new configuration is working we need to create a new image, push the image to our registry and restart our gateway:

```bash
$ ./mvnw spring-boot:build-image -Dspring-boot.build-image.imageName=localhost:5000/apps/gateway
$ docker push localhost:5000/apps/gateway
$ kubectl delete $(kubectl get pod --selector app=gateway -o name)
$ pkill kubectl -9
$ kubectl port-forward services/my-gateway 8080:80 --address 0.0.0.0 > /dev/null 2>&1 &
```

We can now simulate a flood of HTTP request by executing:

```bash
$ curl https://raw.githubusercontent.com/TYsewyn/Getting-started-with-Spring-Cloud/master/hack.sh -o ~/demo/hack.sh && chmod a+x ~/demo/hack.sh
$ sh ~/demo/hack.sh 2 localhost:8080/catalog/items
```

> NOTE: If you see that the requests are still succeeding, check the `X-RateLimit-Remaining` header.
> If the value of this header is -1 there is a problem with the configuration of your rate limiter.
> The easiest way to troubleshoot is to enable debug logging using `logging.level.root: DEBUG`.

While this script is running in our VM we should still be able to access our API from our browser.