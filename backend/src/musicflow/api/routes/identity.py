from __future__ import annotations

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from musicflow.api.dependencies import get_current_identity
from musicflow.db.identities import InternalIdentity

router = APIRouter(prefix="/v1", tags=["identity"])


class CurrentIdentityResponse(BaseModel):
    id: UUID


@router.get("/me", response_model=CurrentIdentityResponse)
async def current_identity(
    identity: Annotated[InternalIdentity, Depends(get_current_identity)],
) -> CurrentIdentityResponse:
    return CurrentIdentityResponse(id=identity.id)
