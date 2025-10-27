# Example App

This is an example app that demonstrates the **Big Bear Universal App Format**.

## Purpose

Use this as a template when creating new apps for the Big Bear ecosystem.

## Structure

- **`app.json`** - Contains all app metadata, configuration, and platform compatibility information
- **`docker-compose.yml`** - Standard Docker Compose file (clean, no platform extensions)

## Key Points

### app.json

The `app.json` file includes:

- **metadata** - Basic app information (id, name, version, description, etc.)
- **visual** - Icons, thumbnails, screenshots
- **resources** - Links to documentation, repository, support
- **technical** - Architectures, ports, main service
- **deployment** - Environment variables, volumes, ports with descriptions
- **ui** - UI scheme, path, tips for users
- **compatibility** - Which platforms support this app
- **tags** - Searchable tags

### docker-compose.yml

The Docker Compose file should be:

- ✅ **Clean** - No platform-specific extensions (no x-casaos, etc.)
- ✅ **Standard** - Valid Docker Compose v3+ format
- ✅ **Portable** - Works with standard `docker compose up`
- ✅ **Relative Paths** - Use `./data` instead of absolute paths
- ✅ **Versioned** - Specify image versions explicitly

## Using This Template

1. **Copy the example:**
   ```bash
   cp -r apps/_example apps/mynewapp
   ```

2. **Edit `app.json`:**
   - Change `id` to your app name (lowercase, hyphens only)
   - Update all metadata fields
   - Set correct image, version, ports
   - Configure environment variables and volumes
   - Set platform compatibility

3. **Edit `docker-compose.yml`:**
   - Use the correct Docker image
   - Configure ports, volumes, environment
   - Keep it clean and standard

4. **Validate:**
   ```bash
   ./scripts/validate-apps.sh -a mynewapp
   ```

5. **Convert:**
   ```bash
   ./scripts/convert-to-platforms.sh -a mynewapp
   ```

## Notes

- The `_example` directory starts with underscore so it's sorted first
- This example won't actually deploy (it uses a fictional image)
- Use this as a reference when creating real apps
- See [SCHEMA.md](../../SCHEMA.md) for complete format documentation

## Real-World Example

For a real app example, check out:
```bash
# After migrating from CasaOS
ls apps/jellyseerr/
```

This will show you how an actual app is structured.
