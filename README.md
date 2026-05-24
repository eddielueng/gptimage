<p align="center"><img src="./data/images/banner.svg" alt="GPT-Image Prompt Gallery by XidaoAPI" width="800" /></p>

<h3 align="center">GPT-Image Prompt Gallery & Generator | Powered by XidaoAPI</h3>

<p align="center">
  <a href="https://github.com/eddielueng/gptimage"><img src="https://img.shields.io/github/stars/eddielueng/gptimage?style=flat-square&color=rgb(25%2C%20121%2C%20255)" alt="Stars"></a>
  <a href="https://github.com/eddielueng/gptimage"><img src="https://img.shields.io/github/forks/eddielueng/gptimage?style=flat-square&color=green" alt="Forks"></a>
  <a href="https://xidaoapi.com"><img src="https://img.shields.io/badge/Powered%20by-XidaoAPI-blueviolet?style=flat-square" alt="XidaoAPI"></a>
</p>

<p align="center">
  <strong>English</strong> | <a href="./README.zh-CN.md">简体中文</a>
</p>

> Browse 400+ GPT-Image prompt cases, fill in your own API Key, and generate images directly.
> Based on [awesome-gpt-image-2](https://github.com/freestylefly/awesome-gpt-image-2) by [freestylefly](https://github.com/freestylefly).

## Features

- **Your Own API Key** — Fill in your API key from [XidaoAPI.com](https://xidaoapi.com), generate images using your own quota
- **Email & Google Login** — Register with email/password or Google OAuth
- **Model Selector** — Choose between `gpt-image`, `gpt-image-2`, `gpt-image-2-c`
- **400+ Prompt Cases** — Browse and copy structured prompts across 12 categories
- **20+ Templates** — Industrial-grade prompt templates for various use cases
- **Local Favorites & History** — Works even without backend, saved in browser

## Quick Start

### 1. Get Your API Key

Visit [XidaoAPI.com](https://xidaoapi.com) to create an account and get your API key.

### 2. Deploy or Run Locally

```bash
# Clone the repo
git clone https://github.com/eddielueng/gptimage.git
cd gptimage
npm install

# Copy env file and fill in your values
cp .env.example .env

# Run locally
npm run dev
```

### 3. Configure Environment

Key variables in `.env`:

```bash
# Supabase (for auth)
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=

# Admin emails (comma-separated)
VITE_SUPER_ADMIN_EMAILS=
SUPER_ADMIN_EMAILS=

# Image generation API
CIYUAN_BASE_URL=https://hk.xidaoapi.com
IMAGE_MODEL=gpt-image-2

# App URL
APP_URL=http://localhost:5173
```

See [.env.example](.env.example) for the full list.

### 4. Setup Supabase Database

Run the SQL migrations in [supabase/combined_migration.sql](supabase/combined_migration.sql) via the Supabase SQL Editor.

## Category Overview

<table>
  <tr>
    <td width="33%" valign="top" align="center">
      <p><strong>UI & Interfaces</strong></p>
      <a href="docs/gallery.md#cat-ui"><img src="data/images/category-covers/ui.jpg" alt="UI" width="220"></a><br>
      <a href="docs/gallery.md#cat-ui"><strong>View Cases</strong></a>
    </td>
    <td width="33%" valign="top" align="center">
      <p><strong>Charts & Infographics</strong></p>
      <a href="docs/gallery.md#cat-infographic"><img src="data/images/category-covers/infographic.jpg" alt="Infographic" width="220"></a><br>
      <a href="docs/gallery.md#cat-infographic"><strong>View Cases</strong></a>
    </td>
    <td width="33%" valign="top" align="center">
      <p><strong>Posters & Typography</strong></p>
      <a href="docs/gallery.md#cat-poster"><img src="data/images/category-covers/poster.jpg" alt="Poster" width="220"></a><br>
      <a href="docs/gallery.md#cat-poster"><strong>View Cases</strong></a>
    </td>
  </tr>
  <tr>
    <td width="33%" valign="top" align="center">
      <p><strong>Products & E-commerce</strong></p>
      <a href="docs/gallery.md#cat-product"><img src="data/images/category-covers/product.jpg" alt="Product" width="220"></a><br>
      <a href="docs/gallery.md#cat-product"><strong>View Cases</strong></a>
    </td>
    <td width="33%" valign="top" align="center">
      <p><strong>Brand & Logos</strong></p>
      <a href="docs/gallery.md#cat-brand"><img src="data/images/category-covers/brand.jpg" alt="Brand" width="220"></a><br>
      <a href="docs/gallery.md#cat-brand"><strong>View Cases</strong></a>
    </td>
    <td width="33%" valign="top" align="center">
      <p><strong>Photography & Realism</strong></p>
      <a href="docs/gallery.md#cat-photo"><img src="data/images/category-covers/photo.jpg" alt="Photo" width="220"></a><br>
      <a href="docs/gallery.md#cat-photo"><strong>View Cases</strong></a>
    </td>
  </tr>
  <tr>
    <td width="33%" valign="top" align="center">
      <p><strong>Illustration & Art</strong></p>
      <a href="docs/gallery.md#cat-illustration"><img src="data/images/category-covers/illustration.jpg" alt="Illustration" width="220"></a><br>
      <a href="docs/gallery.md#cat-illustration"><strong>View Cases</strong></a>
    </td>
    <td width="33%" valign="top" align="center">
      <p><strong>Architecture & Spaces</strong></p>
      <a href="docs/gallery.md#cat-architecture"><img src="data/images/category-covers/architecture.jpg" alt="Architecture" width="220"></a><br>
      <a href="docs/gallery.md#cat-architecture"><strong>View Cases</strong></a>
    </td>
    <td width="33%" valign="top" align="center">
      <p><strong>Full Gallery</strong></p>
      <a href="docs/gallery.md"><img src="data/images/category-covers/gallery.jpg" alt="Gallery" width="220"></a><br>
      <a href="docs/gallery.md"><strong>Open Gallery</strong></a>
    </td>
  </tr>
</table>

## Quick Links

- [Full case gallery](docs/gallery.md)
- [Industrial prompt templates](docs/templates.md)
- [Agent skill: GPT-Image Style Library](agents/skills/gpt-image-2-style-library/SKILL.md)
- [MIT License](LICENSE)

## Attributions

This project is based on [awesome-gpt-image-2](https://github.com/freestylefly/awesome-gpt-image-2) by [freestylefly](https://github.com/freestylefly), licensed under MIT.

The original project organizes 400+ GPT-Image prompt cases and 20+ industrial templates into structured, reusable protocols (Prompt-as-Code). We customized it for [XidaoAPI](https://xidaoapi.com) with:

- User API Key support (generate with your own key)
- Email/password registration & login
- Model selector (gpt-image, gpt-image-2, gpt-image-2-c)
- API endpoint: `https://hk.xidaoapi.com`

Original prompt cases reference public content from [YouMind](https://youmind.com/) and [OpenNana](https://opennana.com/) for learning and research. Copyright belongs to the original authors.

## License

[MIT License](LICENSE) — Free to use, modify, and distribute with license notice preserved.
