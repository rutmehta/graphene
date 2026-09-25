## sample-after-visits.txt

Main-thread header: `4378 Thread_8992773   DispatchQueue_1: com.apple.main-thread  (serial)`. Counts below are inclusive frame occurrences summed across call-tree branches, not additive CPU percentages.

| Samples | Graphene symbol | Raw line |
|---:|---|---:|
| 4378 | `Graphene_main` | 26 |
| 4378 | `static GrapheneApp.$main()` | 27 |

2 distinct Graphene symbols in this main-thread call graph; fewer than 15 are listed when fewer exist.

Top-of-stack section (all threads; cannot be relabeled main-thread-only):
```text
mach_msg2_trap  (in libsystem_kernel.dylib)        13134
        __workq_kernreturn  (in libsystem_kernel.dylib)        13133
        semaphore_wait_trap  (in libsystem_kernel.dylib)        4378
        __psynch_cvwait  (in libsystem_kernel.dylib)        4373
```

## sample-ctrl-tab-pre-input.txt

Main-thread header: `4426 Thread_8992773   DispatchQueue_1: com.apple.main-thread  (serial)`. Counts below are inclusive frame occurrences summed across call-tree branches, not additive CPU percentages.

| Samples | Graphene symbol | Raw line |
|---:|---|---:|
| 4426 | `Graphene_main` | 26 |
| 4426 | `static GrapheneApp.$main()` | 27 |
| 1 | `thunk for @escaping @callee_guaranteed @Sendable (@guaranteed NSTimer) -> ()` | 52 |
| 1 | `closure #5 in AppState.init(directory:clock:sharing:privateMode:)` | 53 |
| 1 | `static MainActor.assumeIsolated<A>(_:file:line:)` | 54 |
| 1 | `closure #1 in static MainActor.assumeIsolated<A>(_:file:line:)` | 55 |
| 1 | `partial apply for thunk for @callee_guaranteed () -> (@out A, @error @owned Error)` | 56 |
| 1 | `thunk for @callee_guaranteed () -> (@out A, @error @owned Error)` | 57 |
| 1 | `partial apply for closure #1 in closure #5 in AppState.init(directory:clock:sharing:privateMode:)` | 58 |
| 1 | `closure #1 in closure #5 in AppState.init(directory:clock:sharing:privateMode:)` | 59 |
| 1 | `AppState.archiveInactiveTabs()` | 60 |
| 1 | `AppState.archiveInactiveTabs(in:)` | 61 |
| 1 | `AppState.archiveHours.getter` | 62 |
| 1 | `BrowserLibrary.archiveHours.getter` | 63 |

14 distinct Graphene symbols in this main-thread call graph; fewer than 15 are listed when fewer exist.

Top-of-stack section (all threads; cannot be relabeled main-thread-only):
```text
mach_msg2_trap  (in libsystem_kernel.dylib)        13278
        __workq_kernreturn  (in libsystem_kernel.dylib)        8851
        semaphore_wait_trap  (in libsystem_kernel.dylib)        4426
        __psynch_cvwait  (in libsystem_kernel.dylib)        4422
```

## sample-ctrl-tab.txt

Main-thread header: `4274 Thread_8992773: Main Thread   DispatchQueue_<multiple>`. Counts below are inclusive frame occurrences summed across call-tree branches, not additive CPU percentages.

| Samples | Graphene symbol | Raw line |
|---:|---|---:|
| 4274 | `Graphene_main` | 26 |
| 4274 | `static GrapheneApp.$main()` | 27 |
| 9 | `protocol witness for View.body.getter in conformance SidebarTab` | 1163 |
| 9 | `SidebarTab.body.getter` | 1164 |
| 5 | `closure #1 in SidebarTab.body.getter` | 1166 |
| 5 | `SidebarTab.rowContent.getter` | 1167 |
| 4 | `closure #1 in SidebarTab.rowContent.getter` | 1171 |
| 4 | `protocol witness for View.body.getter in conformance Sidebar` | 1239 |
| 4 | `Sidebar.body.getter` | 1240 |
| 4 | `closure #1 in Sidebar.body.getter` | 1244 |
| 4 | `closure #3 in closure #1 in Sidebar.body.getter` | 1248 |
| 4 | `ScrollView.init(_:content:)` | 1249 |
| 4 | `closure #1 in closure #3 in closure #1 in Sidebar.body.getter` | 1251 |
| 4 | `protocol witness for Layout.explicitAlignment(of:in:proposal:subviews:cache:) in conformance ShellContentLayout` | 2169 |
| 4 | `protocol witness for Layout.placeSubviews(in:proposal:subviews:cache:) in conformance ShellContentLayout` | 2176 |

98 distinct Graphene symbols in this main-thread call graph; fewer than 15 are listed when fewer exist.

Top-of-stack section (all threads; cannot be relabeled main-thread-only):
```text
__workq_kernreturn  (in libsystem_kernel.dylib)        12813
        mach_msg2_trap  (in libsystem_kernel.dylib)        12307
        __psynch_cvwait  (in libsystem_kernel.dylib)        5712
        semaphore_wait_trap  (in libsystem_kernel.dylib)        4274
        pas_thread_local_cache_for_all  (in JavaScriptCore)        14
        AG::Graph::UpdateStack::update()  (in AttributeGraph)        11
        swift_release  (in libswiftCore.dylib)        11
        <deduplicated_symbol>  (in SwiftUICore)        10
        stop_allocator  (in JavaScriptCore)        10
        AG::Graph::propagate_dirty(AG::AttributeID)  (in AttributeGraph)        8
        swift::MetadataCacheKey::operator==(swift::MetadataCacheKey const&) const  (in libswiftCore.dylib)        8
        scavenger_thread_main  (in JavaScriptCore)        7
        swift_retain  (in libswiftCore.dylib)        7
        AG::Subgraph::update(unsigned int)  (in AttributeGraph)        5
        start_wqthread  (in libsystem_pthread.dylib)        5
        swift_bridgeObjectRetain  (in libswiftCore.dylib)        5
```

## sample-idle.txt

Main-thread header: `4319 Thread_8992773   DispatchQueue_1: com.apple.main-thread  (serial)`. Counts below are inclusive frame occurrences summed across call-tree branches, not additive CPU percentages.

| Samples | Graphene symbol | Raw line |
|---:|---|---:|
| 4318 | `Graphene_main` | 26 |
| 4318 | `static GrapheneApp.$main()` | 27 |
| 1 | `partial apply for thunk for @escaping @isolated(any) @callee_guaranteed @async () -> (@out A)` | 81 |
| 1 | `thunk for @escaping @isolated(any) @callee_guaranteed @async () -> (@out A)` | 82 |
| 1 | `partial apply for closure #1 in closure #4 in AppState.init(directory:clock:sharing:privateMode:)` | 83 |
| 1 | `closure #1 in closure #4 in AppState.init(directory:clock:sharing:privateMode:)` | 84 |
| 1 | `AppState.pollMediaAndDiscard()` | 85 |
| 1 | `AppState.lruVictims(limit:)` | 86 |
| 1 | `getEnumTagSinglePayload for TabLifecycle.Resident` | 89 |
| 1 | `???` | 90 |

10 distinct Graphene symbols in this main-thread call graph; fewer than 15 are listed when fewer exist.

Top-of-stack section (all threads; cannot be relabeled main-thread-only):
```text
mach_msg2_trap  (in libsystem_kernel.dylib)        12954
        __workq_kernreturn  (in libsystem_kernel.dylib)        8634
        __psynch_cvwait  (in libsystem_kernel.dylib)        4610
        semaphore_wait_trap  (in libsystem_kernel.dylib)        4319
```
