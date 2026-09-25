using System;
using System.Collections.Generic;
using GitHub.DistributedTask.Pipelines;
using GitHub.DistributedTask.Pipelines.ContextData;
using GitHub.DistributedTask.WebApi;
using GitHub.Runner.Worker;
using Xunit;

namespace GitHub.Runner.Common.Tests.Worker
{
    public class HomelabJobPolicyL0
    {
        private AgentJobRequestMessage Job()
        {
            // Deserialize the same message type received by the runner.
            return Newtonsoft.Json.JsonConvert.DeserializeObject<AgentJobRequestMessage>(@"{
              'contextData': { 'github': { 't': 2, 'd': [
                { 'k': 'repository', 'v': 'teevik/Config' },
                { 'k': 'repository_id', 'v': '908743957' },
                { 'k': 'repository_owner_id', 'v': '9365365' },
                { 'k': 'ref', 'v': 'refs/heads/main' },
                { 'k': 'workflow_ref', 'v': 'teevik/Config/.github/workflows/nix-cache-tracer.yml@refs/heads/main' },
                { 'k': 'event_name', 'v': 'schedule' }
              ] } },
              'variables': { 'system.workflowFileFullPath': { 'value': 'teevik/Config/.github/workflows/nix-build.yml' } }
            }");
        }

        [Fact]
        public void AllowsNightly() => HomelabJobPolicy.Validate(Job());

        [Fact]
        public void AllowsManualMain()
        {
            var job = Job();
            ((DictionaryContextData)job.ContextData["github"])["event_name"] = new StringContextData("workflow_dispatch");
            HomelabJobPolicy.Validate(job);
        }

        [Theory]
        [InlineData("event_name", "pull_request")]
        [InlineData("event_name", "pull_request_target")]
        [InlineData("event_name", "push")]
        [InlineData("ref", "refs/pull/12/merge")]
        [InlineData("ref", "refs/heads/feature")]
        [InlineData("repository", "attacker/Config")]
        [InlineData("repository_id", "1")]
        [InlineData("repository_owner_id", "1")]
        [InlineData("workflow_ref", "teevik/Config/.github/workflows/evil.yml@refs/heads/main")]
        [InlineData("workflow_ref", "")]
        public void RejectsOtherJobs(string key, string value)
        {
            var job = Job();
            ((DictionaryContextData)job.ContextData["github"])[key] = new StringContextData(value);
            Assert.Throws<InvalidOperationException>(() => HomelabJobPolicy.Validate(job));
        }

        [Fact]
        public void RejectsOtherReusableWorkflow()
        {
            var job = Job();
            job.Variables["system.workflowFileFullPath"] = new VariableValue("teevik/Config/.github/workflows/evil.yml");
            Assert.Throws<InvalidOperationException>(() => HomelabJobPolicy.Validate(job));
        }
    }
}
