const express = require("express");
const path = require("path");
const app = express();
const port = 8080;

/**
 * Midddleware
 */

// Serve static files from the "public" directory
app.use(express.static(path.join(__dirname, "public"), { redirect: false }));

app.use((req, res, next) => {
  // Enable CORS
  res.header("Access-Control-Allow-Origin", "*");
  res.header("Access-Control-Allow-Methods", "*");
  res.header("Access-Control-Allow-Headers", "*");
  res.header("x-powered-by", "serverless-container-framework");
  next();
});

// Enable error handling of promises
const asyncHandler = (fn) => (req, res, next) => {
  return Promise.resolve(fn(req, res, next)).catch(next);
};

/**
 * Routes
 */

// Robots.txt
app.get("/robots.txt", (req, res) => {
  res.type("text/plain");
  res.send(`User-agent: *`);
});

app.options(`*`, (req, res) => {
  res.status(200).send();
});

// Healthcheck
app.get(`/health`, (req, res) => {
  res.status(200).send(`OK`);
});

// Default
app.get(
  `/*`,
  asyncHandler((req, res) => {
    res.send(`
    <html>
      <head>
        <title>Serverless Container Framework</title>
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link href="https://fonts.googleapis.com/css2?family=Roboto+Mono:ital,wght@0,100..700;1,100..700&display=swap" rel="stylesheet">
        <link rel="stylesheet" type="text/css" href="/css/styles.css">
        <link rel="icon" type="image/png" href="/images/favicon.png">
      </head>
      <body>
        <div class="container">
          <img src="/images/logo.png" alt="Logo" class="logo">
          <div class="info">Namespace: ${process.env.SERVERLESS_NAMESPACE}</div>
          <div class="info">Container Name: ${process.env.SERVERLESS_CONTAINER_NAME}</div>
          <div class="info">Stage: ${process.env.SERVERLESS_STAGE}</div>
          <div class="info">Compute Type: ${process.env.SERVERLESS_COMPUTE_TYPE}</div>
          <div class="info">Local: ${process.env.SERVERLESS_LOCAL}</div>
        </div>
      </body>
    </html>
  `);
  })
);

// Catch-all 404 - for any unmatched paths
app.use((req, res) => {
  res.status(404).send(`
    <html>
      <head>
        <title>404 - Page Not Found</title>
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link href="https://fonts.googleapis.com/css2?family=Roboto+Mono:ital,wght@0,100..700;1,100..700&display=swap" rel="stylesheet">
        <link rel="stylesheet" type="text/css" href="/css/styles.css">
        <link rel="icon" type="image/png" href="/images/favicon.png">
      </head>
      <body>
        <div class="container">
          <h1>404 - Page Not Found</h1>
          <a href="/">Return to Home</a>
        </div>
      </body>
    </html>
  `);
});

/**
 * Error Handler
 */
app.use((err, req, res, next) => {
  console.log(err);
  res.status(err.status || 500).json({
    error: err.message || "Internal Server Error",
    message: err.message || "Internal Server Error",
    code: err.code || "internal_error",
    status: err.status,
    // stack: err.stack - Don't include stack trace
  });
});

app.listen(port, "0.0.0.0", () => {
  console.log(`App initialized`);
});
