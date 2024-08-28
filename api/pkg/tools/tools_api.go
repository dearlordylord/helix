package tools

import (
	"context"
	"encoding/json"
	"fmt"
	"html/template"
	"net/http"
	"strings"

	"github.com/getkin/kin-openapi/openapi3"
	oai "github.com/helixml/helix/api/pkg/openai"
	"github.com/helixml/helix/api/pkg/types"
	"github.com/rs/zerolog/log"

	openai "github.com/lukemarsden/go-openai2"
)

func (c *ChainStrategy) prepareRequest(ctx context.Context, tool *types.Tool, action string, params map[string]string) (*http.Request, error) {
	loader := openapi3.NewLoader()

	schema, err := loader.LoadFromData([]byte(tool.Config.API.Schema))
	if err != nil {
		return nil, fmt.Errorf("failed to load openapi spec: %w", err)
	}

	// Based on the operationId get the path and method
	var path, method string

	queryParams := make(map[string]bool)
	pathParams := make(map[string]bool)

	for p, pathItem := range schema.Paths.Map() {
		for m, operation := range pathItem.Operations() {
			if operation.OperationID == action {
				path = p
				method = m

				for _, param := range operation.Parameters {

					switch param.Value.In {
					case "query":
						queryParams[param.Value.Name] = true
					case "path":
						pathParams[param.Value.Name] = true
					}
				}

				break
			}
		}
	}

	if path == "" || method == "" {
		return nil, fmt.Errorf("failed to find path and method for action %s", action)
	}

	// Prepare request
	req, err := http.NewRequestWithContext(ctx, method, tool.Config.API.URL+path, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	for k, v := range tool.Config.API.Headers {
		req.Header.Set(k, v)
	}

	q := req.URL.Query()

	// Add path params
	for k, v := range params {
		if pathParams[k] {
			req.URL.Path = strings.Replace(req.URL.Path, "{"+k+"}", v, -1)
		}

		if queryParams[k] {
			q.Add(k, v)
		}
	}

	req.URL.RawQuery = q.Encode()

	if tool.Config.API.Query != nil {
		q := req.URL.Query()
		for k, v := range tool.Config.API.Query {
			log.Debug().Str("key", k).Str("value", v).Msg("Adding query param")
			q.Add(k, v)
		}

		req.URL.RawQuery = q.Encode()
	}

	req.Header.Set("X-Helix-Tool-Id", tool.ID)
	req.Header.Set("X-Helix-Action-Id", action)

	// TODO: Add body

	return req, nil
}

func (c *ChainStrategy) getAPIRequestParameters(ctx context.Context, sessionID, interactionID string, tool *types.Tool, history []*types.ToolHistoryMessage, action string) (map[string]string, error) {
	systemPrompt, err := c.getApiSystemPrompt(tool)
	if err != nil {
		return nil, fmt.Errorf("failed to prepare system prompt: %w", err)
	}

	userPrompt, err := c.getApiUserPrompt(tool, history, action)
	if err != nil {
		return nil, fmt.Errorf("failed to prepare user prompt: %w", err)
	}

	messages := []openai.ChatCompletionMessage{
		systemPrompt,
		userPrompt,
	}

	req := openai.ChatCompletionRequest{
		Stream:   false,
		Model:    c.cfg.Tools.Model,
		Messages: messages,
	}

	ctx = oai.SetContextValues(ctx, &oai.ContextValues{
		OwnerID:       "system",
		SessionID:     sessionID,
		InteractionID: interactionID,
	})

	ctx = oai.SetStep(ctx, &oai.Step{
		Step: types.LLMCallStepPrepareAPIRequest,
	})

	resp, err := c.apiClient.CreateChatCompletion(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("failed to get response from inference API: %w", err)
	}

	if len(resp.Choices) == 0 {
		return nil, fmt.Errorf("no response from inference API")
	}

	answer := resp.Choices[0].Message.Content

	// var params map[string]string
	params, err := unmarshalParams(answer)
	if err != nil {
		return nil, err
	}

	return params, nil
}

func unmarshalParams(data string) (map[string]string, error) {
	var initial map[string]interface{}
	err := unmarshalJSON(data, &initial)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal response from inference API: %w (%s)", err, data)
	}

	params := make(map[string]string)

	for k, v := range initial {
		// Convert any type of value to string
		if v == nil {
			params[k] = "" // Set empty string if value is nil
		} else {
			params[k] = fmt.Sprintf("%v", v)
		}
	}

	return params, nil
}

func (c *ChainStrategy) getApiSystemPrompt(_ *types.Tool) (openai.ChatCompletionMessage, error) {
	return openai.ChatCompletionMessage{
		Role:    openai.ChatMessageRoleSystem,
		Content: apiSystemPrompt,
	}, nil
}

func (c *ChainStrategy) getApiUserPrompt(tool *types.Tool, history []*types.ToolHistoryMessage, action string) (openai.ChatCompletionMessage, error) {
	// Render template
	apiUserPromptTemplate := apiUserPrompt

	if tool.Config.API.RequestPrepTemplate != "" {
		apiUserPromptTemplate = tool.Config.API.RequestPrepTemplate
	}

	tmpl, err := template.New("api_params").Parse(apiUserPromptTemplate)
	if err != nil {
		return openai.ChatCompletionMessage{}, err
	}

	jsonSpec, err := filterOpenAPISchema(tool, action)
	if err != nil {
		return openai.ChatCompletionMessage{}, err
	}

	// for preparing the API request, we ONLY use the last message for now (but
	// we might want to revisit this, because it could make sense to fill in api
	// params from previous messages)
	currentMessage := history[len(history)-1].Content

	// Render template
	var sb strings.Builder
	err = tmpl.Execute(&sb, struct {
		Schema       string
		Message      string
		Interactions []*types.ToolHistoryMessage
	}{
		Schema:       jsonSpec,
		Message:      currentMessage,
		Interactions: history,
	})

	if err != nil {
		return openai.ChatCompletionMessage{}, err
	}

	return openai.ChatCompletionMessage{
		Role:    openai.ChatMessageRoleUser,
		Content: sb.String(),
	}, nil
}

const apiSystemPrompt = `You are an intelligent machine learning model that can produce REST API's params / query params in json format, given the json schema, user input, data from previous api calls, and current application state.`

const apiUserPrompt = `
Your output must be a valid json, without any commentary or additional formatting.

Examples:

**User Input:** Get project prj_1234 details
**OpenAPI schema path:** /projects/{projectId}
**Verdict:** response should be {"projectId": "prj_1234"}

**User Input:** List all users with status "active"
**OpenAPI schema path:** /users/findByStatus 
**OpenAPI schema parameters:** [
	{
		"name": "status",
		"in": "query",
		"description": "Status values that need to be considered for filter",
		"required": true,
		"type": "array",
		"items": {
			"type": "string",
			"enum": ["active", "pending", "sold"],
			"default": "available"
		}		
	}
]
**Verdict:** response should be:

` + "```" + `json
{
  "status": "active"
}
` + "```" + `

**Response Format:** Always respond with JSON without any commentary, wrapped in markdown json tags, for example:
` + "```" + `json
{
  "parameterName": "parameterValue",
  "parameterName2": "parameterValue2"
} 
` + "```" + `

===END EXAMPLES===
OpenAPI schema: {{.Schema}}

Conversation so far:
{{ range $index, $interaction := .Interactions }}
<{{ $interaction.Role }}_message>{{ $interaction.Content }}</{{ $interaction.Role }}_message>
{{ end }}

Based on the information provided, construct a valid JSON object. In cases where user input does not contain information for a query, DO NOT add that specific query parameter to the output. If a user doesn't provide a required parameter, use sensible defaults for required params, and leave optional params.
`

func filterOpenAPISchema(tool *types.Tool, operationId string) (string, error) {
	loader := openapi3.NewLoader()

	if tool.Config.API == nil || tool.Config.API.Schema == "" {
		return "", fmt.Errorf("tool does not have an API schema")
	}

	schema, err := loader.LoadFromData([]byte(tool.Config.API.Schema))
	if err != nil {
		return "", fmt.Errorf("failed to load openapi spec: %w", err)
	}

	filtered := &openapi3.T{}
	filtered.Info = schema.Info
	filtered.OpenAPI = schema.OpenAPI
	filtered.Paths = &openapi3.Paths{}
	filtered.Components = &openapi3.Components{}

	var usedRefs []string

	for path, pathItem := range schema.Paths.Map() {
		for method, operation := range pathItem.Operations() {
			if operation.OperationID == operationId {
				// filtered.addOperation(path, method, operation)
				filtered.AddOperation(path, method, operation)

				for _, resp := range operation.Responses.Map() {
					jsonBody, ok := resp.Value.Content["application/json"]
					if !ok {
						continue
					}

					if jsonBody.Schema == nil {
						continue
					}

					if jsonBody.Schema.Ref != "" {
						parts := strings.Split(jsonBody.Schema.Ref, "/")
						if len(parts) > 0 {
							usedRefs = append(usedRefs, parts[len(parts)-1])
						}
					}
				}
			}
		}
	}

	if len(usedRefs) > 0 {
		filtered.Components.Schemas = make(map[string]*openapi3.SchemaRef)

		for _, ref := range usedRefs {
			filtered.Components.Schemas[ref] = schema.Components.Schemas[ref]
		}
	}

	jsonSpec, err := json.MarshalIndent(filtered, "", "  ")
	if err != nil {
		return "", fmt.Errorf("failed to marshal openapi spec: %w", err)
	}

	return string(jsonSpec), nil
}

func GetActionsFromSchema(spec string) ([]*types.ToolApiAction, error) {
	loader := openapi3.NewLoader()

	schema, err := loader.LoadFromData([]byte(spec))
	if err != nil {
		return nil, fmt.Errorf("failed to load openapi spec: %w", err)
	}

	var actions []*types.ToolApiAction

	for path, pathItem := range schema.Paths.Map() {

		for method, operation := range pathItem.Operations() {
			description := operation.Summary
			if description == "" {
				description = operation.Description
			}

			if operation.OperationID == "" {
				return nil, fmt.Errorf("operationId is missing for all %s %s", method, path)
			}

			actions = append(actions, &types.ToolApiAction{
				Name:        operation.OperationID,
				Description: description,
				Path:        path,
				Method:      method,
			})
		}
	}

	return actions, nil
}
