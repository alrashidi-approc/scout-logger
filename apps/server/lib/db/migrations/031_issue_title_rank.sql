-- Trust level of issues.title (ids.dart titleRank): a title is only replaced by
-- an equal or higher rank, so a diagnosis headline isn't overwritten by a raw message.
ALTER TABLE issues ADD COLUMN IF NOT EXISTS title_rank SMALLINT NOT NULL DEFAULT 0;
