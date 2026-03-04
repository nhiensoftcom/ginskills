curl -X 'POST' \
  'https://api.styai.app/api/v1/media/remove-background' \
  -H 'accept: application/json' \
  -H 'X-API-Key: REDACTED_STY_AI_API_KEY' \
  -H 'Content-Type: multipart/form-data' \
  -F 'file=@intro-step1.png;type=image/png' \
  -F 'cropToForeground=false' \
  -F 'targetSize=1024 768' \
  -F 'outputFormat=png'


  output
  {
    buffer: "base64",
    contentType: "image/png",
    size: 300000,
    processingTime: 1000,
    sucess: true
  }