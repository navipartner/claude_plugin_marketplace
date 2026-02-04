---
name: get-next-id
description: This skill should be used when the user is working in .al files for Business Central apps and creating new objects or adding new table/tableextension fields or enum/enumextension values.
---

# AL ID Manager

This skill provides instructions for requesting next available IDs from the AL ID Manager service when creating new AL objects, table fields, or enum values.

## Prerequisites

Before requesting an ID, you must read the project's `app.json` to obtain:
- `id` - The application identifier (used as `appId` in API calls)
- `idRanges` - Array of allowed ID ranges with `from` and `to` values

## Configuration

Before using this skill, you must set up your API credentials.

### Config File Location

| Platform | Path |
|----------|------|
| macOS/Linux | `~/.al-id-manager/config.json` |
| Windows | `%USERPROFILE%\.al-id-manager\config.json` |

### Setup Instructions

1. **Check if config exists** - Read the config file from the appropriate path
2. **If missing, create it** - Create the directory and file with this template:

```json
{
  "apiKey": "your-api-key-here",
  "baseUrl": "https://al-id-manager.npretail.io"
}
```

3. **Set secure permissions** (macOS/Linux only):
```bash
chmod 600 ~/.al-id-manager/config.json
```

4. **Replace `your-api-key-here`** with your actual API key from your administrator

### Environment Variable Override

You can override the config file by setting the `AL_ID_MANAGER_API_KEY` environment variable:
- macOS/Linux: `export AL_ID_MANAGER_API_KEY="your-key"`
- Windows: `set AL_ID_MANAGER_API_KEY=your-key`

**Precedence:** Environment variable > Config file > Error (no default)

### Security Warning

⚠️ The API key is passed as a query parameter (`?key=...`). Query parameters may be logged by proxies, browsers, or monitoring tools. Treat API keys as sensitive credentials.

## API Usage

**Base URL:** Read from config `baseUrl` field (default: `https://al-id-manager.npretail.io`)

All requests must include:
- Header: `Content-Type: application/json`
- Query parameter: `?key={apiKey}` (from config or environment variable)

## Endpoints

### 1. Get Next Object ID

Use when creating a new AL object (table, page, codeunit, report, etc.).

**Endpoint:** `POST /api/object/next/{appId}?key={apiKey}`

**Request Body:**
```json
{
  "type": "<object-type>",
  "ranges": [
    { "from": 50000, "to": 99999 }
  ]
}
```

**Supported Object Types:**
`table`, `page`, `codeunit`, `report`, `query`, `xmlport`, `enum`, `enumextension`, `tableextension`, `pageextension`, `reportextension`, `interface`, `permissionset`, `permissionsetextension`, `entitlement`, `controladdin`, `profile`, `pagecustomization`, `dotnet`, `requestpage`

**Example (curl):**
```bash
curl -X POST "https://al-id-manager.npretail.io/api/object/next/your-app-id?key=REDACTED_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"type": "table", "ranges": [{"from": 50000, "to": 99999}]}'
```

### 2. Get Next Table Field ID

Use when adding a new field to a `table` object.

**Endpoint:** `POST /api/table/next/{appId}?key={apiKey}`

**Request Body:**
```json
{
  "tableId": 50100,
  "ranges": [
    { "from": 1, "to": 999999 }
  ]
}
```

**Note:** For table fields, use the default range `[{"from": 1, "to": 999999}]` unless your organization has specific field ID policies.

**Example (curl):**
```bash
curl -X POST "https://al-id-manager.npretail.io/api/table/next/your-app-id?key=REDACTED_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"tableId": 50100, "ranges": [{"from": 1, "to": 999999}]}'
```

### 3. Get Next TableExtension Field ID

Use when adding a new field to a `tableextension` object.

**Endpoint:** `POST /api/tableextension/next/{appId}?key={apiKey}`

**Request Body:**
```json
{
  "tableextensionId": 50100,
  "ranges": [
    { "from": 50000, "to": 99999 }
  ]
}
```

**Note:** For tableextension fields, use `idRanges` from `app.json` (not the default 1-999999 range).

**Example (curl):**
```bash
curl -X POST "https://al-id-manager.npretail.io/api/tableextension/next/your-app-id?key=REDACTED_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"tableextensionId": 50100, "ranges": [{"from": 50000, "to": 99999}]}'
```

### 4. Get Next Enum Value ID

Use when adding a new value to an `enum` object.

**Endpoint:** `POST /api/enum/next/{appId}?key={apiKey}`

**Request Body:**
```json
{
  "enumId": 50100,
  "ranges": [
    { "from": 1, "to": 999999 }
  ]
}
```

**Note:** For enum values, use the default range `[{"from": 1, "to": 999999}]` unless your organization has specific value ID policies.

**Example (curl):**
```bash
curl -X POST "https://al-id-manager.npretail.io/api/enum/next/your-app-id?key=REDACTED_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"enumId": 50100, "ranges": [{"from": 1, "to": 999999}]}'
```

### 5. Get Next EnumExtension Value ID

Use when adding a new value to an `enumextension` object.

**Endpoint:** `POST /api/enumextension/next/{appId}?key={apiKey}`

**Request Body:**
```json
{
  "enumextensionId": 50100,
  "ranges": [
    { "from": 50000, "to": 99999 }
  ]
}
```

**Note:** For enumextension values, use `idRanges` from `app.json` (not the default 1-999999 range).

**Example (curl):**
```bash
curl -X POST "https://al-id-manager.npretail.io/api/enumextension/next/your-app-id?key=REDACTED_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"enumextensionId": 50100, "ranges": [{"from": 50000, "to": 99999}]}'
```

## Response Format

All endpoints return:

```json
{
  "id": 50100,
  "available": true
}
```

- `id` - The allocated ID to use
- `available` - Whether an ID was successfully allocated

If no ID is available in the given ranges:
```json
{
  "id": 0,
  "available": false
}
```

## Workflow

1. **Read app.json** to get `id` and `idRanges`
2. **Determine the ID type** based on what you're creating:
   - New AL object → use object endpoint with matching `type`
   - New table field → use table endpoint with `tableId`
   - New tableextension field → use tableextension endpoint with `tableextensionId`
   - New enum value → use enum endpoint with `enumId`
   - New enumextension value → use enumextension endpoint with `enumextensionId`
3. **Make the API request** with appropriate ranges:
   - Objects, tableextensions, enumextensions: use `idRanges` from app.json
   - Table fields, enum values: use `[{"from": 1, "to": 999999}]`
4. **Use the returned ID** in your AL code

## Range Selection

| Creating | Range Source |
|----------|--------------|
| AL Object (table, page, codeunit, etc.) | `idRanges` from app.json |
| Table field | `[{"from": 1, "to": 999999}]` |
| TableExtension field | `idRanges` from app.json |
| Enum value | `[{"from": 1, "to": 999999}]` |
| EnumExtension value | `idRanges` from app.json |

## Error Handling

If the API returns an error or `available: false`:
1. Check that the `appId` matches the `id` in app.json
2. Verify the ranges are valid (positive integers, `from` <= `to`)
3. Ensure you haven't exhausted all IDs in the given ranges
