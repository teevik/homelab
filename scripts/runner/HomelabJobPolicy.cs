using System;
using GitHub.DistributedTask.Pipelines;
using GitHub.DistributedTask.Pipelines.ContextData;

namespace GitHub.Runner.Worker
{
    // Inspect the authenticated job message BEFORE InitializeJob downloads or
    // executes anything. Workflow env and even always() steps cannot bypass it.
    public static class HomelabJobPolicy
    {
        public static void Validate(AgentJobRequestMessage message)
        {
            if (message.ContextData == null ||
                !message.ContextData.TryGetValue("github", out var raw) ||
                raw is not DictionaryContextData github)
                throw new InvalidOperationException("Homelab runner: missing GitHub job identity");

            string Get(string key) => github.TryGetValue(key, out var value) &&
                value is StringContextData text ? text.Value : "";
            if (Get("repository") != "teevik/Config" ||
                Get("repository_id") != "908743957" ||
                Get("repository_owner_id") != "9365365" ||
                Get("ref") != "refs/heads/main" ||
                Get("workflow_ref") != "teevik/Config/.github/workflows/nix-cache-tracer.yml@refs/heads/main" ||
                (Get("event_name") != "schedule" && Get("event_name") != "workflow_dispatch"))
                throw new InvalidOperationException("Homelab runner accepts only Config nightly jobs on main");

            if (!message.Variables.TryGetValue("system.workflowFileFullPath", out var workflow) ||
                workflow.Value != "teevik/Config/.github/workflows/nix-build.yml")
                throw new InvalidOperationException("Homelab runner requires the approved reusable build workflow");
        }
    }
}
