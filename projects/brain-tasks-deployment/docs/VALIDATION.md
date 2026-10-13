# Validation record

Validation date: **11 October 2026**. This record distinguishes completed checks from infrastructure that still requires AWS access.

## Completed in the preparation workspace

| Check | Result and scope |
|---|---|
| Upstream clone | Original commit `d611aeb7cb0db09b43b5d67cc7171b54f0a1903b`; all four original asset hashes preserved |
| Frontend preparation | Five API references changed in a separate output directory; guarded create/update/delete refresh patches and a new content hash |
| API and release tests | **12 passed** using pytest, FastAPI TestClient and isolated Moto DynamoDB; no live AWS or shared task data used |
| Shell scripts | ShellCheck passed for build, bootstrap, verification and Nginx entrypoint scripts |
| Python files | Compiled successfully; API and manifest rendering exercised by the tests |
| YAML | Kubernetes, Compose and buildspec documents parsed; selectors, probes and container security settings checked |
| Nginx HTTP runtime | Six checks passed: anonymous health 200, anonymous UI/API 401, authenticated root/create route 200, missing asset 404; cache and security headers also checked |
| Terraform | Formatting passed; initialization installed the signed AWS provider and generated the committed provider lock file |
| Browser UI | **Passed 10 checks** in a real headless Chromium browser: initial list, search, filter, direct create route, create/refresh, numeric edit ID, update/refresh, delete, mobile rendering and no JavaScript page errors |

The native Nginx check used the deployment configuration with host paths and the host process user adapted for this environment. It verifies HTTP behavior; it is not proof that a Docker container ran.

There was one non-failing Starlette deprecation warning in the API test run. The test environment uses the explicitly pinned httpx dependency.

Evidence:

- [Original asset hashes](validation/upstream-sha256.json)
- [HTTP check results](validation/http-validation.json)
- [Browser check result](screenshots/browser-validation.json)
- [Desktop screenshot](screenshots/local-desktop.png)
- [Create task screenshot](screenshots/local-create-task.png)
- [Mobile screenshot](screenshots/local-mobile.png)

Browser screenshots use isolated API fixtures with disposable tasks. They demonstrate the prepared frontend and its interactions. They are not screenshots of an AWS deployment.

## Runner validation

The course repository's `.github/workflows/brain-tasks-validation.yml` validates this project folder. It fetches the exact commit with the Git CLI, runs the API/release tests and ShellCheck, runs Terraform provider validation, builds and runs the frontend image, exercises the browser, and runs both application images against local DynamoDB with real HTTP CRUD checks. It saves logs and screenshots as a workflow artifact. It uses no AWS credentials and creates no AWS resources.

Check the actual GitHub Actions run before calling these runner checks successful. Adding the workflow alone is not a successful execution.

## Workspace limitations

- No Docker daemon was available here, so Docker image build/run and Compose integration were not executed locally.
- `terraform validate` could not load the provider because this workspace denies Unix domain sockets. Terraform initialization and formatting succeeded, but provider validation needs the standard runner or your laptop.
- AWS credentials were not available. The AWS console returned **Site Unavailable** in the available browser. No ECR repository, EKS cluster, AWS connection, CodeBuild project or CodePipeline execution was created or verified.
- An actual load balancer ARN exists only after AWS provisioning. The Verify stage and `scripts/get-load-balancer.sh` retrieve it from AWS; this repository does not invent one.

## Before the final AWS submission

Follow the README's authenticated bootstrap and pipeline procedure. Keep the first Terraform apply's pipeline disabled until the AWS GitHub connection is AVAILABLE, namespace/RBAC/configuration exist, and the application password Secret is installed. The pipeline builds immutable frontend and API images, applies the resolved manifests through the native EKS Deploy action, then verifies both rollouts and records the active NLB ARN.

The default port 3000 HTTP listener is an IP-restricted assignment environment. For Internet production traffic, configure an ACM certificate and DNS, remove the cleartext listener, and adapt verification to the HTTPS URL as explained in the README. Basic authentication and a shared task collection support this single-user project; independent user accounts need application-level authorization.

Capture the real AWS screenshots listed in [SUBMISSION.md](SUBMISSION.md) only after deployment. Keep passwords, tokens, private state and unrelated account details out of the public repository.
