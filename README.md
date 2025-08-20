# colby.gg

Personal blog built with Hugo static site generator, hosted on GitHub Pages at [colby.gg](https://colby.gg).

## Prerequisites

- [Hugo Extended](https://gohugo.io/installation/) v0.139.3 or later
- [Go](https://golang.org/dl/) 1.23+ (for theme modules)

## Development

### Local Development Server

Start the development server with draft content enabled:

```bash
hugo server -D
```

**Recommended: Use the run script** which automatically builds the search index and starts the server:

```bash
./run.sh
```

The site will be available at [http://localhost:1313](http://localhost:1313) with live reload.

### Create New Post

Generate a new blog post with date prefix:

```bash
./newpost.sh title-of-my-post
```

#### Old way

```bash
hugo new content posts/$(date +"%Y-%m-%d")-${TITLE}.md
```

Example:

```bash
TITLE="my-new-post" hugo new content posts/$(date +"%Y-%m-%d")-${TITLE}.md
```

### Build for Production

Build the static site:

```bash
hugo --gc --minify
```

Output will be generated in the `public/` directory.

## Content Structure

- `content/posts/` - Blog posts with YYYY-MM-DD-title.md naming convention
- `static/images/` - Post images organized in date-based folders
- `hugo.toml` - Site configuration
- `layouts/` - Custom layout overrides for the theme

## Search Functionality

The site includes full-text search powered by [Pagefind](https://pagefind.app/). Search functionality:

- **Accessible at** `/search/` via the main navigation
- **Keyboard shortcut**: Press `/` to focus the search input
- **Auto-generated index**: Built during site generation
- **Client-side search**: Fast, no server required

The search index is automatically built when using `./run.sh` or during CI/CD deployment.

## Theme

Uses [hugo-theme-m10c](https://github.com/vaga/hugo-theme-m10c) as a Go module. Theme configuration is in `hugo.toml`.

## Deployment

The site automatically deploys to GitHub Pages via GitHub Actions when changes are pushed to the `master` branch. See `.github/workflows/hugo.yaml` for deployment configuration.

## Post Guidelines

- Use TOML front matter with `title`, `date`, `draft`, `toc`, and `tags`
- Place images in `static/images/YYYY-MM-DD-post-title/` folders
- Use tags for categorization
- Set `draft = false` when ready to publish
