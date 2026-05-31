package com.example.controller;

import com.example.model.Product;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.util.List;

@Path("/api/products")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class ProductController {

    @GET
    public List<Product> getAllProducts() {
        return Product.listAll();
    }

    @POST
    @Transactional
    public Product createProduct(Product product) {
        product.persist();
        return product;
    }
}