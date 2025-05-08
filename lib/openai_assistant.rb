require 'faraday'
require 'faraday_middleware'
require 'openai'
require 'json'

API_KEY = ENV['OPENAI_API_KEY']
FILE_PATH = 'tmp/file_upload_test.json'
PROMPT_PATH = 'tmp/prompt.json'

# Initialize Faraday connection
def initialize_connection
  Faraday.new(url: 'https://api.openai.com') do |f|
    f.request :json
    f.response :json
    f.adapter Faraday.default_adapter
  end
end

# Upload the file to OpenAI
def upload_file(client, file_path)
  uploaded_file = client.files.upload(parameters: {
    file: File.open(file_path),
    purpose: "assistants"
  })
  file_id = uploaded_file["id"]
  puts "✅ File uploaded with ID: #{file_id}"
  file_id
end

# Create a new assistant
def create_assistant(client)
  assistant = client.assistants.create(parameters: {
    name: "Data Assistant",
    instructions: "You are a helpful data assistant. Analyze uploaded JSON files and provide insights as instructed.",
    tools: [{ type: "file_search" }],
    model: "gpt-4o-mini"
  })
  assistant_id = assistant["id"]
  puts "✅ Assistant created with ID: #{assistant_id}"
  assistant_id
end

# Create a new thread
def create_thread(client)
  thread = client.threads.create
  thread_id = thread["id"]
  puts "✅ Thread created with ID: #{thread_id}"
  thread_id
end

# Read the prompt from a file
def read_prompt(prompt_path)
  JSON.parse(File.read(prompt_path))["prompt"]
end

# Post a message to the thread
def post_message(conn, thread_id, prompt, file_id)
  message_response = conn.post("/v1/threads/#{thread_id}/messages") do |req|
    req.headers['Authorization'] = "Bearer #{API_KEY}"
    req.headers['OpenAI-Beta'] = 'assistants=v2'
    req.body = {
      role: "user",
      content: prompt,
      attachments: [
        {
          file_id: file_id,
          tools: [{ type: "file_search" }]
        }
      ]
    }
  end

  raise "Message creation failed!" unless message_response.success?
  puts "✅ Message posted to thread."
end

# Trigger the assistant to run
def trigger_run(conn, thread_id, assistant_id)
  run_response = conn.post("/v1/threads/#{thread_id}/runs") do |req|
    req.headers['Authorization'] = "Bearer #{API_KEY}"
    req.headers['OpenAI-Beta'] = 'assistants=v2'
    req.body = { assistant_id: assistant_id }
  end

  raise "Run initiation failed!" unless run_response.success?

  run_id = run_response.body["id"]
  puts "🚀 Run started with ID: #{run_id}"
  run_id
end

# Poll for run completion
def poll_run_status(conn, thread_id, run_id)
  loop do
    status_response = conn.get("/v1/threads/#{thread_id}/runs/#{run_id}") do |req|
      req.headers['Authorization'] = "Bearer #{API_KEY}"
      req.headers['OpenAI-Beta'] = 'assistants=v2'
    end

    break if status_response.body["status"] == "completed"
    sleep 1
  end
  puts "✅ Run completed."
end

# Retrieve and parse the response messages
def retrieve_and_parse_messages(conn, thread_id)
  messages_response = conn.get("/v1/threads/#{thread_id}/messages") do |req|
    req.headers['Authorization'] = "Bearer #{API_KEY}"
    req.headers['OpenAI-Beta'] = 'assistants=v2'
  end

  messages = messages_response.body["data"]
  raw_string = messages.first['content'].first['text']['value']
  cleaned_json_string = raw_string.gsub(/\A```json\n/, '').gsub(/\n```$/, '')
  JSON.parse(cleaned_json_string)
end

# Main function to run the entire process
def run_assistant_flow
  # Initialize OpenAI client
  client = OpenAI::Client.new(access_token: API_KEY)

  # Initialize Faraday connection
  conn = initialize_connection

  # Upload file, create assistant, and create thread
  file_id = upload_file(client, FILE_PATH)
  assistant_id = create_assistant(client)
  thread_id = create_thread(client)

  # Read the prompt from file
  prompt = read_prompt(PROMPT_PATH)

  # Post message with file attachment
  post_message(conn, thread_id, prompt, file_id)

  # Trigger assistant run
  run_id = trigger_run(conn, thread_id, assistant_id)

  # Poll for run completion
  poll_run_status(conn, thread_id, run_id)

  # Retrieve and parse the response
  parsed_json = retrieve_and_parse_messages(conn, thread_id)
  parsed_json
end

# Execute the flow
result = run_assistant_flow
result