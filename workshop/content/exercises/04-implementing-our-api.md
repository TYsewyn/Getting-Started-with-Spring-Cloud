Now we are sure that we are verifying our API it is time to fix our failing tests.
As a first iteration we will create a `CatalogController` and `OrdersController` which will react and respond to the requests our generated test will execute.

```editor:append-lines-to-file
file: ~/demo/shop/src/main/java/com/example/demo/shop/CatalogController.java
text: |
    package com.example.demo.shop;

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

        @GetMapping(value = "/items", produces = { "application/json" })
        public ResponseEntity<String> retrieveAllItems() {
            logger.info("Received request for shop items");
            return ResponseEntity.ok().body("[{ \"id\": \"6b76148d-0fda-4ebf-8966-d91bfaeb0236\", \"img\": \"https://images.unsplash.com/photo-1590688178590-bb8370b70528\", \"name\": \"Breakfast with homemade bread\", \"price\": 16 }, { \"id\": \"52d59380-79da-49d5-9d09-9716e20ccbc4\", \"img\": \"https://images.unsplash.com/photo-1592894869086-f828b161e90a\", \"name\": \"Brisket\", \"price\": 24 }, { \"id\": \"a7be01f8-b76e-4384-bf1d-e69d7bdbe4b4\", \"img\": \"https://images.unsplash.com/photo-1544025162-d76694265947\", \"name\": \"Pork Ribs\", \"price\": 20 }]");
        }
        
    }
```

```editor:append-lines-to-file
file: ~/demo/shop/src/main/java/com/example/demo/shop/OrdersController.java
text: |
    package com.example.demo.shop;

    import java.net.URI;
    import java.util.UUID;

    import org.slf4j.Logger;
    import org.slf4j.LoggerFactory;
    import org.springframework.http.ResponseEntity;
    import org.springframework.web.bind.annotation.PostMapping;
    import org.springframework.web.bind.annotation.RequestMapping;
    import org.springframework.web.bind.annotation.RestController;

    @RestController
    @RequestMapping("/orders")
    public class OrdersController {

        public static final Logger logger = LoggerFactory.getLogger(OrdersController.class);

        @PostMapping(consumes = { "application/json" })
        public ResponseEntity<Void> placeOrder() {
            UUID orderId = UUID.randomUUID();
            logger.info("Created order with id {}", orderId);
            return ResponseEntity.created(URI.create("/orders/" + orderId)).build();
        }
        
    }
```

Before we run our tests we need to update the `BaseTestClass` so that both `RestController`s have been included in our setup.

```editor:select-matching-text
file: ~/demo/shop/src/test/java/com/example/demo/shop/BaseTestClass.java
text: "RestAssuredMockMvc.standaloneSetup();"
```

Replace the highlighted line with the following statement:
```copy
RestAssuredMockMvc.standaloneSetup(new CatalogController(), new OrdersController());
```

Next, run the build again.

```execute
./mvnw clean verify
```

You should see that the API of our application is now behaving like we defined in the contracts.

```
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
```