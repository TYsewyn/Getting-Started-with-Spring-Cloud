In this workshop we will create the backing service of a webshop for people to order take-away food.
The owner decided that they want to have a website which works across all devices and already contacted a web developer.
To be able to work in parallel we decided to use an API first approach.
During the discussion we agreed on the following things:

1. We need to be able to show the list of products the company is selling, so we at least need the following data:

    - The name of the product
    - The price of the product
    - A visually appealing picture of the product

2. We need to be able to accept orders, so we rely on the following data:

    - The customer their name
    - The list of products the customer wants to buy
    - For each product in the list we also need to know how many times the customer wants this product

Next, the web developer shared that the web application will only be able to send and accept data in JSON format.
At the end of the short technical discussion we came to the following conclusion:

1. Getting the items from the menu:
    - HTTP call `GET /catalog/items`
    - Content type of the response `application/json`
    - The product has a UUID
    - The name of the product can only exist out of letters and dashes
    - The price must be a positive number
    - The image should be a URL to a statically hosted image

2. Placing an order:
    - HTTP call `POST /order`
    - Content type of the request `application/json`
    - The customer their name can only contain word characters so we don't exclude anyone
    - The list of products in the order should at least contain 1 item
    - Each item in that list should have a reference to the product, and the amount of the ordered product should be a positive number
    - The web application needs to know if the order got created and where it can find the details