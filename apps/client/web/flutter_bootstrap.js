{{flutter_js}}
{{flutter_build_config}}

// Ship the renderer beside the app rather than requiring a third-party CDN.
_flutter.loader.load({
  config: { canvasKitBaseUrl: 'canvaskit/' },
  onEntrypointLoaded: async engineInitializer => {
    try {
      window.NightcordStartup?.update('renderer');
      const appRunner = await engineInitializer.initializeEngine();
      window.NightcordStartup?.update('app');
      await appRunner.runApp();
    } catch (error) {
      window.NightcordStartup?.fail();
      console.error('Flutter startup failed', error);
    }
  },
}).catch(error => {
  window.NightcordStartup?.fail();
  console.error('Flutter resources failed to load', error);
});
