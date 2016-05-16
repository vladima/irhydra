library hydra;

import 'dart:async' as async;
import 'dart:html';
import 'dart:js' as js;
import 'dart:typed_data' show ByteBuffer, Uint8List;

import 'package:ui_utils/html_utils.dart' show toHtml;
import 'package:ui_utils/xref.dart' show XRef, POPOVER;
import "package:irhydra/src/modes/perf.dart" as perf;
import "package:irhydra/src/modes/v8/v8.dart" as v8;
import 'package:irhydra/src/modes/ir.dart' as IR;
import 'package:irhydra/src/ui/spinner-element.dart';
import 'package:polymer/polymer.dart';
import 'package:irhydra/src/modes/v8/hydrogen_parser.dart' as hydrogen_parser;

final MODES = [
  () => new v8.Mode()
];

class TextFile {
  final file;
  final action;

  TextFile(this.file, this.action);

  load() => _read(file).then(action);

  static _read(file) {
    // We would like to load file as binary to avoid
    // line ending normalization.
    // FileReader.readAsBinaryString is not exposed in Dart
    // so we trampoline through JS.
    async.Completer completer = new async.Completer();
    js.context.callMethod('load', [
      file , completer.complete]);
    return completer.future;
  }
}

timeAndReport(action, report) {
  final stopwatch = new Stopwatch()..start();
  final result = action();
  print(report(stopwatch.elapsedMilliseconds));
  return result;
}

@CustomTag('hydra-app')
class HydraElement extends PolymerElement {
  @observable v8.Mode mode;
  @observable var files;
  @observable var phase;
  @observable var methods;

  @observable var ir;

  @observable var codeMode;

  @observable var crlfDetected = false;
  @observable var sourceAnnotatorFailed = false;

  @observable var sourcePath = toObservable([]);

  @observable var activeTab = "ir";

  @observable var showSource = false;
  @observable var demangleNames = true;
  @observable var sortMethodsBy = "time";

  @observable var progressValue;
  @observable var progressUrl;
  @observable var progressAction;

  @observable var timeline;

  var profile;

  var blockRef;

  HydraElement.created() : super.created();

  attached() {
    super.attached();

    new async.Timer(const Duration(milliseconds: 50), () {
      window.location.hash = "";
    });

    window.onHashChange.listen((e) {
      final to = Uri.parse(e.newUrl).fragment;


      if (to == "source" || to == "ir" || to == "graph") {
        activeTab = to;
        return;
      }

      if (to.startsWith("ir") && activeTab != "ir") {
        activeTab = "ir";

        new async.Timer(const Duration(milliseconds: 50), () {
          irpane.scrollToRow(to.substring("ir-".length));
        });
      }
    });

    window.onPopState.listen((e) {
      if (e.state is String) {
        if (activeTab != "ir")
          activeTab = "ir";

        new async.Timer(const Duration(milliseconds: 50), () {
          irpane.scrollToRow(e.state);
        });
      }
    });

    document.onKeyPress
            .where((e) => e.path.length < 4 && e.keyCode == KeyCode.S)
            .listen((e) {
              showSource = !showSource;
            });

    document.dispatchEvent(new CustomEvent("HydraReady"));
  }

  toggleInterestingMode() {
    showSource = !showSource;
  }

  toggleNameDemangling() {
    demangleNames = !demangleNames;
  }

  closeSplash() {
    js.context.callMethod('DESTROY_SPLASH');
  }

  phaseChanged() {
    closeSplash();
    crlfDetected = false;
    if (phase != null) {
      activeTab = "ir";
      ir = mode.toIr(phase.method, phase, this);

      if (profile != null) {
        profile.attachTo(ir);
      }

      blockRef = new XRef((id) => irpane.rangeContentAsHtmlFull(id));
      sourcePath.clear();
      if (!phase.method.sources.isEmpty) {
        sourcePath.add(phase.method.inlined.first);
      }
    } else {
      ir = null;
    }
  }

  get graphpane => shadowRoot.querySelector("graph-pane");
  get irpane => shadowRoot.querySelector("#ir-pane");
  get sourcePane => shadowRoot.querySelector("#source-pane");

  openCompilation(e, selectedFiles, target) {
    if (selectedFiles.length > 1) {
      reset();
    }
    files = selectedFiles
      .map((file) => new TextFile(file, loadData))
      .toList();
    _loadFiles();
  }

  reloadCurrentFiles(e, detail, target) {
    reset();
    _loadFiles();
  }

  _loadFiles() {
    closeSplash();
    _wait(files, (file) => file.load());
  }

  _wait(data, action) {
    final SpinnerElement spinner = $["spinner"];
    spinner.start();
    return async.Future.forEach(data, action)
      .then((_) => spinner.stop(), onError: (_) => spinner.stop());
  }

  showBlockAction(event, detail, target) {
    blockRef.show(detail.label, detail.blockId);
  }

  hideBlockAction(event, detail, target) {
    blockRef.hide();
  }

  showLegend() => graphpane.showLegend();

  navigateToDeoptAction(event, deopt, target) {
    if (phase.method.inlined.isEmpty)
      return;

    buildStack(position) {
      if (position == null) {
        return [];
      } else {
        final f = phase.method.inlined[position.inlineId];
        return buildStack(f.position)..add(f);
      }
    }

    sourcePath = toObservable(buildStack(deopt.srcPos));
    sourcePane.scrollTo(deopt, activeTab != "source");
  }

  _formatDeoptInfo(deopt) {
    final contents = [];

    var instr = deopt.hir;
    var description;
    if (deopt.hir != null) {
      description = mode.descriptions.lookup("hir", deopt.hir.op);
      if (description == null && deopt.lir != null) {
        description = mode.descriptions.lookup("lir", deopt.lir.op);
        if (description != null) {
          instr = deopt.lir;
        }
      }
    } else {
      try {
        description = toHtml((querySelector('[dependent-code-descriptions]') as TemplateElement).content
            .querySelector("[data-reason='${deopt.reason}']").clone(true));
      } catch (e) { }
    }

    final connector = (deopt.reason == null) ? "at" : "due to";
    contents.add("<h4 class='deopt-header deopt-header-${deopt.type}'><span class='first-word'>${deopt.type}</span> deoptimization ${connector}</h4>");

    if (deopt.reason != null) {
      contents.add("<p><strong>${deopt.reason}</strong></p>");
    }

    if (instr != null) {
      if (deopt.reason != null) {
        contents.add("<h4>at</h4>");
      }
      contents.add(irpane.rangeContentAsHtmlFull(instr.id));
    }

    if (description != null) {
      contents.add(description);
    }

    final raw = new PreElement()
        ..appendText(deopt.raw.join('\n'));
    contents.add(toHtml(raw));

    return contents.join("\n");
  }

  final deoptPopover = new XRef((x) => x, POPOVER);

  enterDeoptAction(event, detail, target) {
    deoptPopover.show(detail.target, _formatDeoptInfo(detail.deopt));
  }

  leaveDeoptAction(event, detail, target) {
    deoptPopover.hide();
  }

  reset() {
    mode = methods = null;
    demangleNames = true;
    profile = null;
    sortMethodsBy = "time";
    crlfDetected = sourceAnnotatorFailed = false;
  }

  methodsChanged() {
    codeMode = "none";
    activeTab = "ir";
    phase = ir = null;
  }

  _loadProfile(text) {
    try {
      profile = perf.parse(text);
    } catch (e, stack) {
      print("ERROR loading profile");
      print("${e}");
      print("${stack}");
      return;
    }
    _attachProfile();
  }

  _attachProfile() {
    if (methods != null && profile != null) {
      try {
        profile.attachAll(mode, methods);
        sortMethodsBy = "ticks";
      } catch (e, stack) {
        print("ERROR while attaching profile");
        print(e);
        print(stack);
      }
    }
  }

  loadProfile(e, selectedFiles, target) {
    final profileFiles = selectedFiles
      .map((file) => new TextFile(file, _loadProfile))
      .toList();
    files = []
      ..addAll(files)
      ..addAll(profileFiles);
    _wait(profileFiles, (file) => file.load());
  }

  /** Load data from the given textual artifact if any mode can handle it. */
  loadData(data) {
    // Warn about Windows-style (CRLF) line endings.
    // Don't normalize the input: V8 writes code trace in
    // binary mode (retaining original line endings) so
    // in theory everything should just work.
    //crlfDetected = crlfDetected || text.contains("\r\n");
    if (mode == null) {
      mode = new v8.Mode();
    }

    if (data is String) {
      mode.load(data);
    }
    else {
      var hydrogenLog = convertHydrogenLog(data);
      mode.load(hydrogenLog);
    }

    timeline = mode.timeline;

    final re = new RegExp(r"\$\d+$");
    demangleNames = !mode.methods.any((m) => re.hasMatch(m.name.full));

    methods = toObservable(mode.methods);
    closeSplash();
  }

  List<IR.Method> convertHydrogenLog(List<js.JsObject> objects) {
    List<IR.Method> methods = [];
    for(var o in objects) {
      var name = o["name"];
      var optId = o["optId"];
      var phases = o["phases"];
      var irName = new IR.Name(name["full"], name["source"], name["short"]);
      var method = new IR.Method(irName, optimizationId: optId);
      methods.add(method);

      for (var phase in phases) {
        var name = phase["name"];
        var startLine = phase["startLine"];
        var endLine = phase["endLine"];
        var irPhase = new IR.Phase(method, name, ir: deferredText(startLine, endLine));
        method.phases.add(irPhase);
      }
    }
    return methods;
  }

  static deferredText(int startLine, int endLine) => () => js.context.callMethod("getText", [startLine, endLine]);
}
