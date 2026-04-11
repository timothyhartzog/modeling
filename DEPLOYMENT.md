# 🚀 GitHub Pages Deployment Guide

## ✅ Current Setup

This repository is configured for automatic GitHub Pages deployment:
- **GitHub Actions workflow** (`.github/workflows/publish.yml`) — Auto-builds and deploys on push to `main`
- **Quarto configuration** (`output/_quarto.yml`) — Website with responsive design
- **Built website** (`output/_site/`) — Static HTML ready to deploy

## 🔧 Initial Setup (One-Time)

### Enable GitHub Pages

1. Go to **Settings** → **Pages**
2. Under "Build and deployment":
   - **Source**: Select "Deploy from a branch"
   - **Branch**: Select `gh-pages` / `/root`
   - Click **Save**

### Enable GitHub Actions

1. Settings → **Actions** → **General**
2. Select "Allow all actions and reusable workflows"
3. Click **Save**

## 📤 Deployment Workflow

### Automatic (Recommended)

Every push to `main` automatically:
1. Builds the website
2. Deploys to `gh-pages` branch
3. Updates your site in ~5 minutes

```bash
git add .
git commit -m "Update curriculum"
git push origin main

# GitHub Actions handles the rest!
```

### Check Status
- Go to **Actions** tab
- View the latest workflow run
- Check build logs if needed

### Manual Testing
```bash
cd output
quarto render          # Build locally
quarto preview         # View at http://localhost:4200
```

## 🌐 Website URL

Once deployed:
```
https://timothyhartzog.github.io/modeling/
```

> First deployment takes 2-5 minutes. Refresh your browser after pushing.

## 🎨 Customization

### Change Theme
Edit `output/_quarto.yml`:
```yaml
format:
  html:
    theme: journal  # Options: cosmo, darkly, flatly, journal, lux, etc.
```

### Update Navigation
Edit `output/_quarto.yml`, `website.sidebar.contents` section.

## 🔄 Updating Content

### Add New Textbook
1. Generate chapter in `output/generated/NEWID.qmd`
2. Add to sidebar in `_quarto.yml`
3. Commit and push

### Update Homepage
Edit `output/index.qmd` and push.

## 🐛 Troubleshooting

### Workflow Fails
1. Check **Actions** tab for error details
2. Common issues:
   - Invalid YAML in `_quarto.yml`
   - Missing file references
   - Syntax errors in `.qmd` files

### Site Not Updating
1. Wait 5-10 minutes
2. Hard refresh browser (Cmd+Shift+R)
3. Verify workflow ran (Actions tab)
4. Check Pages settings (gh-pages branch)

## 📊 Performance

- **Build time**: ~2-3 minutes
- **Site size**: ~45MB
- **Deployment time**: ~5 minutes
- **Caching**: Instant on subsequent visits

---

For issues, check the GitHub Actions logs or create an issue.
