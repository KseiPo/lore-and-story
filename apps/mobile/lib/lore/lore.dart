/// The `lore/` slice: lore model, entity-tree walk, convention matcher (pure),
/// and the browse/editor/preview UI.
///
/// The loader port (Story 2.1a) lands here in Epic 2; project-config resolution
/// (Story 1.3) is the slice's first inhabitant. All depend inward on the
/// `storage/` slice's [RepoStorage] port.
library;

export 'project_config.dart';
