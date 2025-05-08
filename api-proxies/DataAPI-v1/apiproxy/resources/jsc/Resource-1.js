var url = JSON.parse(context.getVariable("storage.location"));

if (url) {
  url = url.replace("https://", "");
  context.setVariable("storage.location", url);
}