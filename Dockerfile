# Node 20 base — Playwright and all browsers are installed explicitly below
# rather than relying on Microsoft's pre-built Playwright image.
FROM node:20-bookworm

WORKDIR /app

# Install only the @playwright/test package (browsers installed separately below)
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts

# Install Playwright browsers (chromium, firefox, webkit) plus their OS-level deps
RUN npx playwright install --with-deps

# Copy test files
COPY playwright.config.ts ./
COPY tests/ ./tests/

# Default: run all tests, generating both the HTML report and CI-friendly line output
CMD ["npx", "playwright", "test", "--reporter=html,line"]
