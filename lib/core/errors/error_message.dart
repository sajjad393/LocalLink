String errorMessage(Object error) =>
    error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
