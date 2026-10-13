#!/usr/bin/env python3
"""Produce the single, resolved artifact consumed by CodePipeline's EKS action."""
import argparse
import ipaddress
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def render(image, api_image, certificate=None, source_cidrs=None):
    for uri in [image, api_image]:
        if not re.fullmatch(r"[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com(?:\.cn)?/[a-z0-9._/-]+@sha256:[a-f0-9]{64}", uri):
            raise ValueError("Use full ECR image URIs pinned to sha256 digests")
    if not source_cidrs:
        raise ValueError("Supply permitted load balancer source CIDRs")
    source_cidrs = [str(ipaddress.ip_network(cidr.strip())) for cidr in source_cidrs.split(",")]
    docs = []
    for name in ["api-service.yaml", "api-deployment.yaml", "deployment.yaml", "service.yaml", "hpa.yaml", "pdb.yaml", "api-pdb.yaml"]:
        value = (ROOT / "k8s" / name).read_text().replace("__IMAGE_URI__", image).replace("__API_IMAGE_URI__", api_image)
        if name == "service.yaml":
            value = value.replace("  type: LoadBalancer\n", "  type: LoadBalancer\n  loadBalancerSourceRanges:\n" +
                                  "".join(f"    - {cidr}\n" for cidr in source_cidrs))
        if name == "service.yaml" and certificate:
            if not re.fullmatch(r"arn:aws(?:-cn|-us-gov)?:acm:[a-z0-9-]+:[0-9]{12}:certificate/[a-zA-Z0-9-]+", certificate):
                raise ValueError("Invalid ACM certificate ARN")
            value = value.replace("  annotations:\n", "  annotations:\n"
                                  f"    service.beta.kubernetes.io/aws-load-balancer-ssl-cert: {certificate}\n"
                                  "    service.beta.kubernetes.io/aws-load-balancer-ssl-ports: '443'\n")
            value += "    - name: https\n      port: 443\n      targetPort: http\n      protocol: TCP\n"
        if "__IMAGE_URI__" in value or "__API_IMAGE_URI__" in value:
            raise ValueError("Unresolved image placeholder")
        docs.append(value.rstrip())
    return "\n---\n".join(docs) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", required=True)
    parser.add_argument("--api-image", required=True)
    parser.add_argument("--certificate")
    parser.add_argument("--source-cidrs", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(render(args.image, args.api_image, args.certificate, args.source_cidrs))
    print(f"Rendered {output} with digest-pinned image")


if __name__ == "__main__":
    main()
