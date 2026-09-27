import "server-only";

import { getVercelStatus, type VercelInfrastructureResult } from "../infrastructure-monitoring";
import { fetchInfrastructureJson, readFiniteNumber } from "./infrastructure-http";

type RecordValue = Record<string, unknown>;

export async function getVercelInfrastructure(signal: AbortSignal): Promise<VercelInfrastructureResult> {
  const token = process.env.VERCEL_ACCESS_TOKEN;
  if (!token) throw new Error("Vercel unavailable");

  const configuredProject = process.env.VERCEL_PROJECT_ID?.trim() || "patrigest";
  const configuredScope = process.env.VERCEL_ORG_ID?.trim();
  const projectUrl = new URL(`https://api.vercel.com/v9/projects/${encodeURIComponent(configuredProject)}`);
  if (configuredScope) projectUrl.searchParams.set("teamId", configuredScope);
  const projectData = await fetchInfrastructureJson(projectUrl, token, signal) as RecordValue;
  const projectId = typeof projectData.id === "string" ? projectData.id : null;
  const scope = configuredScope || (typeof projectData.accountId === "string" ? projectData.accountId : null);
  if (!projectId) throw new Error("Vercel project unavailable");

  const deploymentsUrl = new URL("https://api.vercel.com/v7/deployments");
  deploymentsUrl.searchParams.set("projectId", projectId);
  deploymentsUrl.searchParams.set("target", "production");
  deploymentsUrl.searchParams.set("limit", "1");
  if (scope) deploymentsUrl.searchParams.set("teamId", scope);
  const deploymentData = await fetchInfrastructureJson(deploymentsUrl, token, signal) as RecordValue;
  const deployments = Array.isArray(deploymentData.deployments) ? deploymentData.deployments : [];
  const deployment = deployments[0] as RecordValue | undefined;
  const state = typeof deployment?.readyState === "string" ? deployment.readyState : typeof deployment?.state === "string" ? deployment.state : null;
  if (!deployment || !state) throw new Error("Vercel deployment unavailable");

  const createdAt = readFiniteNumber(deployment.createdAt ?? deployment.created);
  const meta = deployment.meta && typeof deployment.meta === "object" ? deployment.meta as RecordValue : {};
  const commit = [meta.githubCommitSha, meta.gitCommitSha].find((value) => typeof value === "string") as string | undefined;
  const status = getVercelStatus(state);
  if (status === "unavailable") throw new Error("Vercel deployment state unavailable");
  return {
    provider: "vercel",
    status,
    checkedAt: new Date().toISOString(),
    deploymentState: state,
    deployedAt: new Date(createdAt).toISOString(),
    commitSha: commit ? commit.slice(0, 7) : null,
  };
}
