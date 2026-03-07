POST
/api/v1/jobs/createTask
Create Task
Create a new generation task

Request Parameters
The API accepts a JSON payload with the following structure:

Request Body Structure
{
  "model": "string",
  "callBackUrl": "string (optional)",
  "input": {
    // Input parameters based on form configuration
  }
}
Root Level Parameters
model
Required
string
The model name to use for generation

Example:

"bytedance/v1-pro-image-to-video"
callBackUrl
Optional
string
Callback URL for task completion notifications. Optional parameter. If provided, the system will send POST requests to this URL when the task completes (success or failure). If not provided, no callback notifications will be sent.

Example:

"https://your-domain.com/api/callback"
Input Object Parameters
The input object contains the following parameters based on the form configuration:

input.prompt
Required
string
The text prompt used to generate the video

Max length: 10000 characters
Example:

"A golden retriever dashing through shallow surf at the beach, back angle camera low near waterline, splashes frozen in time, blur trails in waves and paws, afternoon sun glinting off wet fur, overcast day, dramatic clouds"
input.image_url
Required
string(URL)
The URL of the image used to generate video

Please provide the URL of the uploaded file; Accepted types: image/jpeg, image/png, image/webp; Max size: 10.0MB
Example:

"https://file.aiquickdraw.com/custom-page/akr/section-images/1755179021328w1nhip18.webp"
input.resolution
Optional
string
Video resolution - 480p for faster generation, 720p for balance, 1080p for higher quality

Available options:

480p
-
480p
720p
-
720p
1080p
-
1080p
Example:

"720p"
input.duration
Optional
string
Duration of the video in seconds

Available options:

5
-
5s
10
-
10s
Example:

"5"
input.camera_fixed
Optional
boolean
Whether to fix the camera position

Boolean value (true/false)
Example:

false
input.seed
Optional
number
Random seed to control video generation. Use -1 for random.

Min: -1, Max: 2147483647, Step: 1
Example:

-1
input.enable_safety_checker
Optional
boolean
The safety checker is always enabled in Playground. It can only be disabled by setting false through the API.

Boolean value (true/false)
Example:

true
Request Example

cURL

JavaScript

Python
curl -X POST "https://api.kie.ai/api/v1/jobs/createTask" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{
    "model": "bytedance/v1-pro-image-to-video",
    "callBackUrl": "https://your-domain.com/api/callback",
    "input": {
      "prompt": "A golden retriever dashing through shallow surf at the beach, back angle camera low near waterline, splashes frozen in time, blur trails in waves and paws, afternoon sun glinting off wet fur, overcast day, dramatic clouds",
      "image_url": "https://file.aiquickdraw.com/custom-page/akr/section-images/1755179021328w1nhip18.webp",
      "resolution": "720p",
      "duration": "5",
      "camera_fixed": false,
      "seed": -1,
      "enable_safety_checker": true
    }
}'
Response Example
{
  "code": 200,
  "message": "success",
  "data": {
    "taskId": "task_12345678"
  }
}
Response Fields
code
Status code, 200 for success, others for failure
message
Response message, error description when failed
data.taskId
Task ID for querying task status
Callback Notifications
When you provide the callBackUrl parameter when creating a task, the system will send POST requests to the specified URL upon task completion (success or failure).

Success Callback Example
{
    "code": 200,
    "data": {
        "completeTime": 1755599644000,
        "costTime": 8,
        "createTime": 1755599634000,
        "model": "bytedance/v1-pro-image-to-video",
        "param": "{\"callBackUrl\":\"https://your-domain.com/api/callback\",\"model\":\"bytedance/v1-pro-image-to-video\",\"input\":{\"prompt\":\"A golden retriever dashing through shallow surf at the beach, back angle camera low near waterline, splashes frozen in time, blur trails in waves and paws, afternoon sun glinting off wet fur, overcast day, dramatic clouds\",\"image_url\":\"https://file.aiquickdraw.com/custom-page/akr/section-images/1755179021328w1nhip18.webp\",\"resolution\":\"720p\",\"duration\":\"5\",\"camera_fixed\":false,\"seed\":-1,\"enable_safety_checker\":true}}",
        "resultJson": "{\"resultUrls\":[\"https://example.com/generated-image.jpg\"]}",
        "state": "success",
        "taskId": "e989621f54392584b05867f87b160672",
        "failCode": null,
        "failMsg": null,
    },
    "msg": "Playground task completed successfully."
}
Failure Callback Example
{
    "code": 501,
    "data": {
        "completeTime": 1755597081000,
        "costTime": 0,
        "createTime": 1755596341000,
        "failCode": "500",
        "failMsg": "Internal server error",
        "model": "bytedance/v1-pro-image-to-video",
        "param": "{\"callBackUrl\":\"https://your-domain.com/api/callback\",\"model\":\"bytedance/v1-pro-image-to-video\",\"input\":{\"prompt\":\"A golden retriever dashing through shallow surf at the beach, back angle camera low near waterline, splashes frozen in time, blur trails in waves and paws, afternoon sun glinting off wet fur, overcast day, dramatic clouds\",\"image_url\":\"https://file.aiquickdraw.com/custom-page/akr/section-images/1755179021328w1nhip18.webp\",\"resolution\":\"720p\",\"duration\":\"5\",\"camera_fixed\":false,\"seed\":-1,\"enable_safety_checker\":true}}",
        "state": "fail",
        "taskId": "bd3a37c523149e4adf45a3ddb5faf1a8",
        "resultJson": null,
    },
    "msg": "Playground task failed."
}
Important Notes
The callback content structure is identical to the Query Task API response
The param field contains the complete Create Task request parameters, not just the input section
If callBackUrl is not provided, no callback notifications will be sent

GET
/api/v1/jobs/recordInfo
Query Task
Query task status and results by task ID

Request Example

cURL

JavaScript

Python
curl -X GET "https://api.kie.ai/api/v1/jobs/recordInfo?taskId=task_12345678" \
  -H "Authorization: Bearer YOUR_API_KEY"
Response Example
{
  "code": 200,
  "message": "success",
  "data": {
    "taskId": "task_12345678",
    "model": "bytedance/v1-pro-image-to-video",
    "state": "success",
    "param": "{\"model\":\"bytedance/v1-pro-image-to-video\",\"callBackUrl\":\"https://your-domain.com/api/callback\",\"input\":{\"prompt\":\"A golden retriever dashing through shallow surf at the beach, back angle camera low near waterline, splashes frozen in time, blur trails in waves and paws, afternoon sun glinting off wet fur, overcast day, dramatic clouds\",\"image_url\":\"https://file.aiquickdraw.com/custom-page/akr/section-images/1755179021328w1nhip18.webp\",\"resolution\":\"720p\",\"duration\":\"5\",\"camera_fixed\":false,\"seed\":-1,\"enable_safety_checker\":true}}",
    "resultJson": "{\"resultUrls\":[\"https://example.com/generated-image.jpg\"]}",
    "failCode": "",
    "failMsg": "",
    "costTime": 0,
    "completeTime": 1698765432000,
    "createTime": 1698765400000
  }
}
Response Fields
code
Status code, 200 for success, others for failure
message
Response message, error description when failed
data.taskId
Task ID
data.model
Model used for generation
data.state
Generation state
data.param
Complete Create Task request parameters as JSON string (includes model, callBackUrl, input and all other parameters)
data.resultJson
Result JSON string containing generated media URLs
data.failCode
Error code (when generation failed)
data.failMsg
Error message (when generation failed)
data.completeTime
Completion timestamp
data.createTime
Creation timestamp
data.costTime
Cost time in milliseconds
State Values
waiting
Waiting for generation
queuing
In queue
generating
Generating
success
Generation successful
fail
Generation failed


example input 
GET
/api/v1/jobs/recordInfo
Query Task
Query task status and results by task ID

Request Example

cURL

JavaScript

Python
curl -X GET "https://api.kie.ai/api/v1/jobs/recordInfo?taskId=task_12345678" \
  -H "Authorization: Bearer YOUR_API_KEY"
Response Example
{
  "code": 200,
  "message": "success",
  "data": {
    "taskId": "task_12345678",
    "model": "bytedance/v1-pro-image-to-video",
    "state": "success",
    "param": "{\"model\":\"bytedance/v1-pro-image-to-video\",\"callBackUrl\":\"https://your-domain.com/api/callback\",\"input\":{\"prompt\":\"A golden retriever dashing through shallow surf at the beach, back angle camera low near waterline, splashes frozen in time, blur trails in waves and paws, afternoon sun glinting off wet fur, overcast day, dramatic clouds\",\"image_url\":\"https://file.aiquickdraw.com/custom-page/akr/section-images/1755179021328w1nhip18.webp\",\"resolution\":\"720p\",\"duration\":\"5\",\"camera_fixed\":false,\"seed\":-1,\"enable_safety_checker\":true}}",
    "resultJson": "{\"resultUrls\":[\"https://example.com/generated-image.jpg\"]}",
    "failCode": "",
    "failMsg": "",
    "costTime": 0,
    "completeTime": 1698765432000,
    "createTime": 1698765400000
  }
}
Response Fields
code
Status code, 200 for success, others for failure
message
Response message, error description when failed
data.taskId
Task ID
data.model
Model used for generation
data.state
Generation state
data.param
Complete Create Task request parameters as JSON string (includes model, callBackUrl, input and all other parameters)
data.resultJson
Result JSON string containing generated media URLs
data.failCode
Error code (when generation failed)
data.failMsg
Error message (when generation failed)
data.completeTime
Completion timestamp
data.createTime
Creation timestamp
data.costTime
Cost time in milliseconds
State Values
waiting
Waiting for generation
queuing
In queue
generating
Generating
success
Generation successful
fail
Generation failed


ouput
{
  "resultUrls": [
    "https://file.aiquickdraw.com/custom-page/akr/section-images/17551796948046brblmi1.mp4"
  ]
}