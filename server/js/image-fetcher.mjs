import { writeFile } from 'node:fs/promises'

const MAX_IMAGE_BYTES = 15 * 1024 * 1024
const defaultImageAccept = 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8'
const [rawUrl, imagePath, typePath, rawConfig = '{}'] = process.argv.slice(2)

function finish(payload) {
  process.stdout.write(JSON.stringify(payload))
}

function fail(error) {
  finish({ ok: false, error })
}

function imageTypeFromHeader(value) {
  const contentType = value?.split(';')[0]?.trim().toLowerCase() ?? ''
  return contentType.startsWith('image/') ? contentType : ''
}

function sniff(bytes) {
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'image/jpeg'
  if (
    bytes[0] === 0x89 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x4e &&
    bytes[3] === 0x47 &&
    bytes[4] === 0x0d &&
    bytes[5] === 0x0a &&
    bytes[6] === 0x1a &&
    bytes[7] === 0x0a
  ) {
    return 'image/png'
  }
  const head = new TextDecoder().decode(bytes.slice(0, 256)).toLowerCase()
  if (head.startsWith('gif87a') || head.startsWith('gif89a')) return 'image/gif'
  if (head.startsWith('riff') && head.slice(8, 12) === 'webp') return 'image/webp'
  if (head.includes('<svg')) return 'image/svg+xml'
  if (head.slice(4, 8) === 'ftyp' && head.includes('avif')) return 'image/avif'
  return ''
}

function parseConfig(value) {
  try {
    const parsed = JSON.parse(value || '{}')
    return parsed && typeof parsed === 'object' ? parsed : {}
  } catch {
    return {}
  }
}

function helperProxyUrl(config) {
  const explicit = config.proxyUrl || config.proxy_url || process.env.VENERA_IMAGE_PROXY_URL || ''
  if (explicit) return explicit
  const helperBase = config.helperUrl || config.helper_url || process.env.VENERA_WEB_HELPER_URL || process.env.VENERA_HELPER_URL || ''
  if (!helperBase) return ''
  return new URL('/proxy', helperBase).toString()
}

function requestHeaders(config) {
  const imageConfig = config.imageConfig || config.image_config || {}
  const headers = {
    Accept: defaultImageAccept,
    'User-Agent': 'Venera-WebPWA/0.1',
    ...(imageConfig.headers || {}),
    ...(config.headers || {})
  }
  const userAgent = config.userAgent || config.user_agent || imageConfig.userAgent || imageConfig.user_agent
  const referer = config.referer || config.referrer || imageConfig.referer || imageConfig.referrer
  const cookie = config.cookie || imageConfig.cookie
  if (userAgent) headers['User-Agent'] = String(userAgent)
  if (referer) headers.Referer = String(referer)
  if (cookie) headers.Cookie = String(cookie)
  return headers
}

async function fetchImage(url, headers, signal, proxyUrl) {
  if (!proxyUrl) return fetch(url, { headers, signal })
  const response = await fetch(proxyUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ url: String(url), method: 'GET', headers, bytes: true }),
    signal
  })
  if (!response.ok) return response
  const payload = await response.json()
  return new Response(Buffer.from(payload.bodyBase64 || '', 'base64'), {
    status: payload.status,
    headers: payload.headers || {}
  })
}

try {
  if (!rawUrl || !imagePath || !typePath) {
    fail('missing image fetch arguments')
    process.exit(0)
  }

  const url = new URL(rawUrl)
  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    fail('image url must use http or https')
    process.exit(0)
  }

  const config = parseConfig(rawConfig)
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), 25000)
  const response = await fetchImage(url, requestHeaders(config), controller.signal, helperProxyUrl(config))
  clearTimeout(timer)

  if (!response.ok) {
    fail(`upstream returned ${response.status}`)
    process.exit(0)
  }

  const contentLength = Number(response.headers.get('content-length') ?? 0)
  if (contentLength > MAX_IMAGE_BYTES) {
    fail('image is too large')
    process.exit(0)
  }

  const buffer = new Uint8Array(await response.arrayBuffer())
  if (buffer.byteLength > MAX_IMAGE_BYTES) {
    fail('image is too large')
    process.exit(0)
  }

  const contentType = imageTypeFromHeader(response.headers.get('content-type')) || sniff(buffer)
  if (!contentType) {
    fail('upstream did not return an image')
    process.exit(0)
  }

  await writeFile(imagePath, buffer)
  await writeFile(typePath, contentType)
  finish({ ok: true, content_type: contentType, size: buffer.byteLength })
} catch (error) {
  fail(error instanceof Error ? error.message : String(error))
}
