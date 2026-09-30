/// Where a harness should open. Cmd-T allocates a temporary destination first;
/// other entry points allocate a new tab only when a harness is ready.
enum HarnessPlacement {
  currentTab,
  newTab;

  String get title => this == newTab ? 'New Tab' : 'New Pane';
  String get action =>
      this == newTab ? 'Open in new swarm' : 'Add to this swarm';
  String get createAction =>
      this == newTab ? 'Create in new swarm' : 'Create in this swarm';
}
