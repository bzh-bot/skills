#!/usr/bin/env python3
"""bank_connect.py — reusable the accounting backend XML-RPC connection.

Env (exported by $BACKEND_ENV_FILE):
    BACKEND_URL, BACKEND_DB, BACKEND_USER, BACKEND_API_KEY  (or BACKEND_PASSWORD fallback)

Usage:
    from bank_connect import connect, search_read, search_count
    db, uid, key, models = connect()
    rows = search_read(models, db, uid, key, "account.journal", [], ["id","name"])
"""
import os
import xmlrpc.client


def connect():
    url = os.environ["BACKEND_URL"]
    db = os.environ["BACKEND_DB"]
    user = os.environ["BACKEND_USER"]
    key = os.environ.get("BACKEND_API_KEY") or os.environ["BACKEND_PASSWORD"]
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, user, key, {})
    if not uid:
        raise RuntimeError("the accounting backend authentication failed")
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")
    return db, uid, key, models


def search_read(models, db, uid, key, model, domain, fields, limit=0, offset=0, order=""):
    """Convenience wrapper for search_read."""
    kwargs = {"fields": fields}
    if limit:
        kwargs["limit"] = limit
    if offset:
        kwargs["offset"] = offset
    if order:
        kwargs["order"] = order
    return models.execute_kw(db, uid, key, model, "search_read", [domain], kwargs)


def search_count(models, db, uid, key, model, domain):
    return models.execute_kw(db, uid, key, model, "search_count", [domain])