"""Builds the database connection string from the environment.

On EKS the pod gets AWS credentials from Pod Identity, reads the password from
the Secrets Manager secret RDS manages (DB_SECRET_ARN), and connects over TLS.
Locally, docker compose passes DB_USER and DB_PASSWORD instead.
"""

import json
import os


def password_from_secret(secret_string: str) -> tuple[str, str]:
    """RDS-managed secrets are JSON: {"username": "...", "password": "..."}."""
    data = json.loads(secret_string)
    return data["username"], data["password"]


def fetch_secret(secret_arn: str, region: str | None) -> str:
    import boto3

    client = boto3.client("secretsmanager", region_name=region)
    return client.get_secret_value(SecretId=secret_arn)["SecretString"]


def conninfo_from_env(env: dict[str, str] | None = None, fetch=fetch_secret) -> str:
    env = dict(os.environ) if env is None else env
    host = env["DB_HOST"]
    port = env.get("DB_PORT", "5432")
    name = env.get("DB_NAME", "shoplane")
    sslmode = env.get("DB_SSLMODE", "require")

    if env.get("DB_SECRET_ARN"):
        user, password = password_from_secret(fetch(env["DB_SECRET_ARN"], env.get("AWS_REGION")))
    else:
        user, password = env["DB_USER"], env["DB_PASSWORD"]

    from psycopg.conninfo import make_conninfo

    return make_conninfo(
        host=host,
        port=port,
        dbname=name,
        user=user,
        password=password,
        sslmode=sslmode,
        connect_timeout=5,
        application_name="shoplane-catalog",
    )
