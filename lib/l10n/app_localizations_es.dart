// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'kOS TV';

  @override
  String get animeMarkerFiller => 'Relleno';

  @override
  String get animeMarkerMixed => 'Mixto';

  @override
  String get animeMarkerAnimeCanon => 'Canon del anime';

  @override
  String get animeMarkerMangaCanon => 'Canon del manga';

  @override
  String get animeMarkerSubbed => 'Subtitulado';

  @override
  String get animeMarkerDubbed => 'Doblado';

  @override
  String get animeMarkerSubbedAndDubbed => 'Subtitulado/Doblado';

  @override
  String get animeMarkerSubbedShort => 'Sub';

  @override
  String get animeMarkerDubbedShort => 'Dob';

  @override
  String get animeMarkerSubbedAndDubbedShort => 'Sub/Dob';

  @override
  String get animeMarkerPending => 'Pendiente';

  @override
  String get animeMarkerRecap => 'Recapitulación';

  @override
  String get interfaceLanguage => 'Idioma de la interfaz';

  @override
  String get systemLanguageDefault => 'Predeterminado del sistema';

  @override
  String get signIn => 'Iniciar sesión';

  @override
  String get signingIn => 'Iniciando sesión...';

  @override
  String get empty => 'Vacío';

  @override
  String connectingToServer(String serverName) {
    return 'Conectando con $serverName';
  }

  @override
  String get quickConnect => 'Quick Connect';

  @override
  String get password => 'Contraseña';

  @override
  String get username => 'Nombre de usuario';

  @override
  String get quickConnectInstruction =>
      'Introduce este código en el panel web de tu servidor:';

  @override
  String get quickConnectScanHint =>
      'O escanea esto con un móvil que tenga la sesión iniciada en tu servidor';

  @override
  String get quickConnectTapOrScanHint =>
      'Toca para aprobar en tu navegador, o escanea esto con otro dispositivo';

  @override
  String get timesUpTitle => 'Se acabó el tiempo';

  @override
  String get timesUpMessage => 'Esta cuenta no está disponible ahora mismo.';

  @override
  String timesUpResumesToday(String time) {
    return 'Podrás volver a usarla hoy a las $time.';
  }

  @override
  String timesUpResumesTomorrow(String time) {
    return 'Podrás volver a usarla mañana a las $time.';
  }

  @override
  String timesUpResumesOn(String day, String time) {
    return 'Podrás volver a usarla el $day a las $time.';
  }

  @override
  String get waitingForAuthorization => 'Esperando autorización...';

  @override
  String get back => 'Atrás';

  @override
  String get serverUnavailable => 'Servidor no disponible';

  @override
  String get loginFailed => 'Error de inicio de sesión';

  @override
  String get loginForbidden =>
      'Esta cuenta no puede iniciar sesión ahora mismo. Puede que esté fuera de su horario permitido, bloqueada o desactivada. Inténtalo más tarde o pregunta a un administrador.';

  @override
  String quickConnectUnavailable(String detail) {
    return 'QuickConnect no disponible: $detail';
  }

  @override
  String quickConnectUnavailableWithStatus(String status, String detail) {
    return 'QuickConnect no disponible ($status): $detail';
  }

  @override
  String get whosWatching => '¿Quién está viendo?';

  @override
  String get signedInOnThisDevice => 'Sesión iniciada en este dispositivo';

  @override
  String get pinRequired => 'Se requiere PIN';

  @override
  String get passwordRequired => 'Se requiere contraseña';

  @override
  String continueAsUser(String name) {
    return 'Continuar como $name';
  }

  @override
  String switchToUser(String name) {
    return 'Cambiar a $name';
  }

  @override
  String signedInAsOnServer(String user, String server) {
    return 'Sesión iniciada como $user en $server';
  }

  @override
  String kostvSignedInAs(String user) {
    return 'Sesión iniciada como $user';
  }

  @override
  String get accountActive => 'Activo';

  @override
  String get addUser => 'Añadir usuario';

  @override
  String get selectServer => 'Seleccionar servidor';

  @override
  String appVersionFooter(String version) {
    return 'kOS TV versión $version';
  }

  @override
  String get savedServers => 'Servidores guardados';

  @override
  String get discoveredServers => 'Servidores descubiertos';

  @override
  String get noneFound => 'Ninguno encontrado';

  @override
  String get unableToConnectToServer => 'No se puede conectar al servidor';

  @override
  String get addServer => 'Añadir servidor';

  @override
  String get embyConnect => 'Emby Connect';

  @override
  String get removeServer => 'Eliminar servidor';

  @override
  String removeServerConfirmation(String serverName) {
    return '¿Eliminar \"$serverName\" de tus servidores?';
  }

  @override
  String get cancel => 'Cancelar';

  @override
  String get remove => 'Quitar';

  @override
  String get connectToServer => 'Conectar al servidor';

  @override
  String get serverAddress => 'Dirección del servidor';

  @override
  String get serverAddressHint => 'https://tu-servidor.ejemplo.com';

  @override
  String get connect => 'Conectar';

  @override
  String get secureStorageUnavailable => 'Almacenamiento seguro no disponible';

  @override
  String get secureStorageUnavailableMessage =>
      'kOS TV no pudo acceder al llavero del sistema. Puedes seguir iniciando sesión, pero el almacenamiento seguro de tokens podría no estar disponible hasta que desbloquees el llavero.';

  @override
  String get ok => 'Aceptar';

  @override
  String get settingsAppearanceTheme => 'Tema de la aplicación';

  @override
  String get detailScreenStyle => 'Estilo de la pantalla de detalles';

  @override
  String get detailScreenStyleSubtitle =>
      'El aspecto que tiene una película o serie al abrirla.';

  @override
  String get detailScreenStyleMoonfin => 'Clásico';

  @override
  String get detailScreenStyleModern => 'Moderno';

  @override
  String get detailScreenStyleSpotlight => 'Foco';

  @override
  String get spotlightMoreActions => 'Más acciones';

  @override
  String get spotlightCastCrewStudios => 'Reparto, equipo y estudios';

  @override
  String get spotlightChaptersExtras => 'Capítulos y extras';

  @override
  String get spotlightFileDetails => 'Detalles del archivo';

  @override
  String get spotlightSimilarRecommendations => 'Similares y recomendaciones';

  @override
  String get spotlightSeasonsEpisodes => 'Temporadas y episodios';

  @override
  String get spotlightMoreEpisodes => 'Más episodios';

  @override
  String get spotlightFilmography => 'Filmografía';

  @override
  String get spotlightCollectionsCard => 'Colecciones';

  @override
  String get spotlightPlaylistOrder => 'Orden de reproducción';

  @override
  String get spotlightMoviesAndShows => 'Películas y series';

  @override
  String spotlightPeopleCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personas',
      one: '1 persona',
    );
    return '$_temp0';
  }

  @override
  String spotlightStudiosCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count estudios',
      one: '1 estudio',
    );
    return '$_temp0';
  }

  @override
  String spotlightChaptersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count capítulos',
      one: '1 capítulo',
    );
    return '$_temp0';
  }

  @override
  String spotlightExtrasCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count extras',
      one: '1 extra',
    );
    return '$_temp0';
  }

  @override
  String spotlightSeasonsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count temporadas',
      one: '1 temporada',
    );
    return '$_temp0';
  }

  @override
  String spotlightEpisodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodios',
      one: '1 episodio',
    );
    return '$_temp0';
  }

  @override
  String spotlightMoviesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count películas',
      one: '1 película',
    );
    return '$_temp0';
  }

  @override
  String spotlightShowsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count series',
      one: '1 serie',
    );
    return '$_temp0';
  }

  @override
  String spotlightTracksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pistas',
      one: '1 pista',
    );
    return '$_temp0';
  }

  @override
  String spotlightItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos',
      one: '1 elemento',
    );
    return '$_temp0';
  }

  @override
  String spotlightAlbumsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count álbumes',
      one: '1 álbum',
    );
    return '$_temp0';
  }

  @override
  String spotlightCollectionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count colecciones',
      one: '1 colección',
    );
    return '$_temp0';
  }

  @override
  String spotlightTitlesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count títulos',
      one: '1 título',
    );
    return '$_temp0';
  }

  @override
  String get detailScreenStyleNouveau => 'Nuevo';

  @override
  String get detailScreenStyleMinimalist => 'Minimalista';

  @override
  String get detailScreenStyleStage => 'Escenario';

  @override
  String get detailScreenStylePremiere => 'Estreno';

  @override
  String get detailScreenStyleQuickLook => 'Vistazo rápido';

  @override
  String get detailScreenStyleFrost => 'Escarcha';

  @override
  String get quickLookOpenFullPage => 'Abrir página completa';

  @override
  String get quickLookBackToClose => 'Atrás para cerrar';

  @override
  String quickLookSeasonPlayed(int played, int total) {
    return '$played de $total';
  }

  @override
  String get expandedTabs => 'Pestañas expandidas';

  @override
  String get expandedTabsSubtitle =>
      'Muestra automáticamente el contenido de las pestañas al navegar por ellas. Desactívalo para abrir y cerrar cada pestaña manualmente.';

  @override
  String get showTechnicalDetails => 'Mostrar detalles técnicos';

  @override
  String get showTechnicalDetailsSubtitle =>
      'Muestra el códec, la resolución y la información del stream en el resumen del banner';

  @override
  String get recommendationSystem => 'Sistema de recomendaciones';

  @override
  String get recommendationSystemSubtitle =>
      'Usa kOS TV Recomienda (un algoritmo sobre tu propia biblioteca), Jellyfin Recomienda (el motor del servidor) o las métricas de similitud en línea de TMDb.';

  @override
  String get recommendationSystemMoonfin => 'kOS TV Recomienda';

  @override
  String get recommendationSystemJellyfin => 'Jellyfin Recomienda';

  @override
  String get recommendationSystemTmdb => 'Similitud de TMDb';

  @override
  String get recommendationsApplyParentalRatingCap =>
      'Aplicar límite de clasificación a las recomendaciones';

  @override
  String get recommendationsApplyParentalRatingCapSubtitle =>
      'Limita las sugerencias de kOS TV Recomienda según la clasificación parental del contenido de referencia';

  @override
  String get interfaceStyle => 'Estilo de la interfaz';

  @override
  String get interfaceStyleSubtitle =>
      'Automático se adapta a tu dispositivo. Elige Apple o Material para forzar un aspecto.';

  @override
  String get interfaceStyleAutomatic => 'Automático';

  @override
  String get interfaceStyleApple => 'Apple';

  @override
  String get interfaceStyleMaterial => 'Material';

  @override
  String get interfaceLayout => 'Diseño de interfaz';

  @override
  String get interfaceLayoutSubtitle =>
      'Cambia el diseño detectado cuando este dispositivo se reconozca mal. Reinicia kOS TV para aplicar los cambios.';

  @override
  String get interfaceLayoutAutomatic => 'Automático';

  @override
  String get interfaceLayoutTv => 'TV';

  @override
  String get interfaceLayoutDesktop => 'Escritorio';

  @override
  String get interfaceLayoutPhone => 'Teléfono';

  @override
  String get glassQuality => 'Calidad del cristal';

  @override
  String get oledMode => 'Modo OLED';

  @override
  String get oledModeSubtitle =>
      'Acentúa los negros y enriquece las ilustraciones. Funciona mejor en pantallas OLED.';

  @override
  String get oledModeSubtle => 'Sutil';

  @override
  String get oledModeVivid => 'Vívido';

  @override
  String get glassQualitySubtitle =>
      'Automático elige el mejor efecto de cristal para este dispositivo. Completo fuerza el desenfoque real; Reducido usa un cristal ligero que ahorra GPU.';

  @override
  String get glassQualityAuto => 'Automático';

  @override
  String get glassQualityFull => 'Completo';

  @override
  String get glassQualityReduced => 'Reducido';

  @override
  String get performanceMode => 'Rendimiento';

  @override
  String get performanceModeSubtitle =>
      'Automático mide este dispositivo y reduce el consumo en los que tienen poca memoria: guarda menos imágenes en memoria y muestra los tráileres como imágenes fijas. Se aplica del todo en el próximo inicio.';

  @override
  String get performanceModeAuto => 'Automático';

  @override
  String get performanceModeStandard => 'Estándar';

  @override
  String get performanceModeReduced => 'Reducido';

  @override
  String get rendererMode => 'Renderizado';

  @override
  String get rendererModeSubtitle =>
      'Automático usa Impeller en los dispositivos cuya gráfica lo ejecuta con fluidez y Skia en el resto. Selecciona Skia si las animaciones o el vídeo se ven mal. Se aplica en el próximo inicio.';

  @override
  String get rendererModeAuto => 'Automático';

  @override
  String get rendererModeSkia => 'Skia';

  @override
  String get trailerPreviewHeldBack =>
      'Desactivado porque el rendimiento está en Reducido en este dispositivo';

  @override
  String get settingsAppearanceThemeSubtitle =>
      'Usa un tema completamente personalizado y cambia entre una interfaz inspirada en Apple o en Material.';

  @override
  String get customThemeTitle => 'Tema personalizado';

  @override
  String get customThemeSubtitle =>
      'Los temas personalizados modifican los elementos visuales de todo kOS TV. Elige una de estas opciones según tu estilo.';

  @override
  String get keyboardStyle => 'Estilo de teclado';

  @override
  String get keyboardStyleDescription =>
      'Nativo usa el teclado de la propia tele. Clásico es el teclado original de la app. Cristal es un panel esmerilado con teclas más grandes. Acoplado ocupa la parte inferior de la pantalla y muestra lo que escribes encima de las teclas.';

  @override
  String get keyboardStyleNative => 'Nativo';

  @override
  String get keyboardStyleClassic => 'Clásico';

  @override
  String get keyboardStyleGlass => 'Cristal';

  @override
  String get keyboardStyleDocked => 'Acoplado';

  @override
  String get keyboardSpace => 'espacio';

  @override
  String get keyboardHoldForAccents => 'mantener pulsado para acentos';

  @override
  String get keyboardClose => 'cerrar';

  @override
  String get controller => 'Mando';

  @override
  String get gamepadNavigation => 'Navegación con mando';

  @override
  String get gamepadNavigationDescription =>
      'Permite que un mando de juegos conectado mueva el foco y seleccione elementos';

  @override
  String get themeMoonfin => 'kOS TV';

  @override
  String get themeMoonfinSubtitle => 'El aspecto limpio por defecto.';

  @override
  String get themeNeonPulse => 'Pulso de neón';

  @override
  String get themeNeonPulseSubtitle =>
      'Estilo Synthwave con brillo magenta, texto cian y contraste cromado más fuerte';

  @override
  String get themeGlass => 'Cristal';

  @override
  String get themeGlassSubtitle =>
      'Estilo de cristal líquido con un fondo degradado en movimiento, superficies esmeriladas y acento azul de Apple';

  @override
  String get theme8BitHero => 'Héroe de 8 bits';

  @override
  String get theme8BitHeroSubtitle =>
      'Estilo retro de pixel art con una paleta contundente, bordes cuadriculados, sombras marcadas y una fuente de píxeles';

  @override
  String get embyConnectSignInSubtitle =>
      'Inicia sesión con tu cuenta de Emby Connect';

  @override
  String get emailOrUsername => 'Correo electrónico o nombre de usuario';

  @override
  String get selectAServer => 'Selecciona un servidor';

  @override
  String get tryAgain => 'Reintentar';

  @override
  String get noLinkedServers =>
      'No hay servidores vinculados a esta cuenta de Emby Connect';

  @override
  String get invalidEmbyConnectCredentials =>
      'Credenciales de Emby Connect no válidas';

  @override
  String get invalidEmbyConnectLogin =>
      'Nombre de usuario o contraseña de Emby Connect no válidos';

  @override
  String get embyConnectExchangeNotSupported =>
      'El servidor no admite el intercambio de Emby Connect';

  @override
  String get embyConnectNetworkError =>
      'Error de red al contactar con Emby Connect o el servidor seleccionado';

  @override
  String get signInWithPlex => 'Iniciar sesión con Plex';

  @override
  String get plexLinkInstructions =>
      'Ve a plex.tv/link en cualquier dispositivo e introduce este código';

  @override
  String get plexOpenLink => 'Abrir plex.tv/link';

  @override
  String get plexWaitingForApproval => 'Esperando a que apruebes el código...';

  @override
  String get plexSignInWithPassword => 'Iniciar sesión con una contraseña';

  @override
  String get plexVerificationCode => 'Código de verificación';

  @override
  String get plexNoServers =>
      'No se han encontrado servidores Plex en esta cuenta';

  @override
  String get loadingLinkedServers => 'Cargando servidores vinculados...';

  @override
  String get connectingToServerEllipsis => 'Conectando al servidor...';

  @override
  String get noReachableAddress => 'No se proporcionó una dirección accesible';

  @override
  String get invalidServerExchangeResponse =>
      'Respuesta no válida del punto de intercambio del servidor';

  @override
  String unableToConnectTo(String target) {
    return 'No se puede conectar a $target';
  }

  @override
  String get exitApp => '¿Salir de kOS TV?';

  @override
  String get exitAppConfirmation => '¿Estás seguro de que quieres salir?';

  @override
  String get exit => 'Salir';

  @override
  String get gameMenu => 'Menú';

  @override
  String get gamePaused => 'En pausa';

  @override
  String get gameSaveState => 'Guardar estado';

  @override
  String get games => 'Juegos';

  @override
  String get gameLoadState => 'Cargar estado';

  @override
  String get gameFastForward => 'Avance rápido';

  @override
  String get gameOrientation => 'Orientación de juego';

  @override
  String get gameOrientationSubtitle => 'Orientación de la pantalla al jugar';

  @override
  String get landscape => 'Horizontal';

  @override
  String get portrait => 'Vertical';

  @override
  String get gameEmulatorSettings => 'Ajustes del emulador';

  @override
  String get gameNoCoreOptions => 'Este núcleo no tiene opciones ajustables.';

  @override
  String get gameHoldToOpenMenu => 'Mantén pulsado para abrir el menú';

  @override
  String get gameKeepPlaying => 'Seguir jugando';

  @override
  String get gameSaveAndExit => 'Guardar y salir';

  @override
  String get gameExitGame => 'Salir del juego';

  @override
  String get gameSavingBeforeExit => 'Guardando…';

  @override
  String get gameSaveFailedStillPlaying =>
      'No se ha podido guardar la partida. Sigues jugando.';

  @override
  String get gamePlaybackUnsupported =>
      'Este dispositivo aún no admite la reproducción de juegos.';

  @override
  String get noHomeRowsLoaded => 'No se pudieron cargar las filas del inicio';

  @override
  String get noHomeRowsHint =>
      'Intenta actualizar o reducir las secciones activas del inicio.';

  @override
  String get retryHomeRows => 'Reintentar filas del inicio';

  @override
  String get guide => 'Guía';

  @override
  String get recordings => 'Grabaciones';

  @override
  String get schedule => 'Programación';

  @override
  String get series => 'Series';

  @override
  String get noItemsFound => 'No se encontraron elementos';

  @override
  String get home => 'Inicio';

  @override
  String get browseAll => 'Explorar todo';

  @override
  String get genres => 'Géneros';

  @override
  String get collectionPlaceholder =>
      'Los elementos de la colección aparecerán aquí';

  @override
  String get browseByLetter => 'Explorar por letra';

  @override
  String get alphabeticalBrowsePlaceholder =>
      'La exploración alfabética aparecerá aquí';

  @override
  String get suggestions => 'Sugerencias';

  @override
  String get suggestionsPlaceholder =>
      'Los elementos sugeridos aparecerán aquí';

  @override
  String get failedToLoadLibraries => 'Error al cargar las bibliotecas';

  @override
  String get noLibrariesFound => 'No se encontraron bibliotecas';

  @override
  String get library => 'Biblioteca';

  @override
  String get displaySettings => 'Ajustes de visualización';

  @override
  String get allGenres => 'Todos los géneros';

  @override
  String get noGenresFound => 'No se encontraron géneros';

  @override
  String failedToLoadFolderError(String error) {
    return 'No se pudo cargar la carpeta: $error';
  }

  @override
  String get thisFolderIsEmpty => 'Esta carpeta está vacía';

  @override
  String itemCountLabel(int count) {
    return '$count elementos';
  }

  @override
  String get failedToLoadFavorites => 'Error al cargar los favoritos';

  @override
  String get retry => 'Reintentar';

  @override
  String get noFavoritesYet => 'Aún no hay favoritos';

  @override
  String get favorites => 'Favoritos';

  @override
  String totalCountItems(int count) {
    return '$count elementos';
  }

  @override
  String get continuing => 'En emisión';

  @override
  String get ended => 'Finalizada';

  @override
  String get sortAndFilter => 'Ordenar y filtrar';

  @override
  String get type => 'Tipo';

  @override
  String get sortBy => 'Ordenar por';

  @override
  String get display => 'Visualización';

  @override
  String get imageType => 'Tipo de imagen';

  @override
  String get posterSize => 'Tamaño del póster';

  @override
  String get small => 'Pequeño';

  @override
  String get medium => 'Mediano';

  @override
  String get large => 'Grande';

  @override
  String get extraLarge => 'Muy grande';

  @override
  String get uiScaleGrandparents => 'Abuelos';

  @override
  String get uiScaleGreatGrandparents => 'Bisabuelos';

  @override
  String get scrollDirection => 'Dirección de desplazamiento';

  @override
  String get scrollDirectionVertical => 'Vertical';

  @override
  String get scrollDirectionHorizontal => 'Horizontal';

  @override
  String libraryGenresTitle(String name) {
    return '$name — Géneros';
  }

  @override
  String get views => 'Vistas';

  @override
  String get albums => 'Álbumes';

  @override
  String get albumArtists => 'Artistas de álbum';

  @override
  String get artists => 'Artistas';

  @override
  String get bookmarks => 'Marcadores';

  @override
  String get noSavedBookmarks =>
      'Aún no hay marcadores guardados para este título.';

  @override
  String get openBook => 'Abrir libro';

  @override
  String get chapter => 'Capítulo';

  @override
  String get page => 'Página';

  @override
  String get bookmark => 'Marcador';

  @override
  String get justNow => 'Ahora mismo';

  @override
  String minutesAgo(int count) {
    return 'hace $count min';
  }

  @override
  String hoursAgo(int count) {
    return 'hace $count h';
  }

  @override
  String daysAgo(int count) {
    return 'hace $count d';
  }

  @override
  String get discoverySubjects => 'Temas de descubrimiento';

  @override
  String get apply => 'Aplicar';

  @override
  String get openLink => 'Abrir enlace';

  @override
  String get scanWithYourPhone => 'Escanea con tu teléfono';

  @override
  String get audiobookGenres => 'Géneros de audiolibros';

  @override
  String get scrollLeft => 'Desplazar a la izquierda';

  @override
  String get scrollRight => 'Desplazar a la derecha';

  @override
  String get scrollToTop => 'Volver arriba';

  @override
  String get couldNotLoadGenre =>
      'No se pudo cargar este género en este momento.';

  @override
  String get continueReading => 'Continuar leyendo';

  @override
  String get savedHighlights => 'Destacados guardados';

  @override
  String get continueListening => 'Continuar escuchando';

  @override
  String get listen => 'Escuchar';

  @override
  String get resume => 'Reanudar';

  @override
  String get failedToLoadLibrary => 'Error al cargar la biblioteca';

  @override
  String get popularNow => 'Popular ahora';

  @override
  String get savedForLater => 'Guardado para después';

  @override
  String get topListens => 'Más escuchados';

  @override
  String get unreadDiscoveries => 'Descubrimientos sin leer';

  @override
  String get pickUpAgain => 'Retomar';

  @override
  String get bookHighlightsDescription =>
      'Tus libros con destacados, favoritos o progreso de lectura.';

  @override
  String get handPickedFromLibrary => 'Seleccionados de tu biblioteca.';

  @override
  String get handPickedFromListeningQueue =>
      'Seleccionados de tu cola de escucha.';

  @override
  String get booksWithHighlights =>
      'Libros con destacados, favoritos o progreso de lectura.';

  @override
  String get jumpBackNarration =>
      'Vuelve a la narración sin tener que buscar dónde te quedaste.';

  @override
  String get unreadBooksReady =>
      'Libros sin leer listos para la próxima hora de tranquilidad.';

  @override
  String get quickAccessFavorites =>
      'Acceso rápido a los libros a los que siempre vuelves.';

  @override
  String get searchAudiobooks => 'Buscar audiolibros';

  @override
  String get searchYourLibrary => 'Buscar en tu biblioteca';

  @override
  String get pickUpStory => 'Retoma la historia donde la dejaste';

  @override
  String get savedPlacesChapters =>
      'Tus lugares guardados y capítulos sin terminar';

  @override
  String authorsCount(int count) {
    return '$count autores';
  }

  @override
  String genresCount(int count) {
    return '$count géneros';
  }

  @override
  String percentCompleted(int percent) {
    return '$percent% completado';
  }

  @override
  String get readyWhenYouAre => 'Listo cuando tú lo estés';

  @override
  String get details => 'Detalles';

  @override
  String get listeningRoom => 'Sala de escucha';

  @override
  String get bookmarksAndProgress => 'Marcadores y progreso';

  @override
  String titlesArrangedForBrowsing(int count) {
    return '$count títulos organizados para explorar pensando en la lectura.';
  }

  @override
  String get titles => 'Títulos';

  @override
  String get allTitles => 'Todos los títulos';

  @override
  String get authors => 'Autores';

  @override
  String get browseByAuthor => 'Explorar por autor';

  @override
  String get browseByGenre => 'Explorar por género';

  @override
  String get discover => 'Descubrir';

  @override
  String get noBookmarkedItems => 'Aún no hay elementos marcados';

  @override
  String get nothingMatchesSection =>
      'Todavía no hay nada en esta sección. Prueba otra pestaña o vuelve cuando termine de sincronizarse la biblioteca.';

  @override
  String get audiobooks => 'Audiolibros';

  @override
  String noLabelFound(String label) {
    return 'No se han encontrado $label';
  }

  @override
  String get folder => 'Carpeta';

  @override
  String get filters => 'Filtros';

  @override
  String get readingStatus => 'Estado de lectura';

  @override
  String get playedStatus => 'Estado de reproducción';

  @override
  String get readStatus => 'Leído';

  @override
  String get watched => 'Visto';

  @override
  String get unread => 'Sin leer';

  @override
  String get unwatched => 'No visto';

  @override
  String get seriesStatus => 'Estado de la serie';

  @override
  String get allLibraries => 'Todas las bibliotecas';

  @override
  String get books => 'Libros';

  @override
  String get latestBooks => 'Últimos libros';

  @override
  String get latestAudiobooks => 'Últimos audiolibros';

  @override
  String get latestComics => 'Últimos cómics';

  @override
  String get comics => 'Cómics';

  @override
  String bookSeriesItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count libros',
      one: '1 libro',
    );
    return '$_temp0';
  }

  @override
  String get bookFormatBook => 'Libro';

  @override
  String get bookFormatAudiobook => 'Audiolibro';

  @override
  String get bookFormatComic => 'Cómic';

  @override
  String get noBooksFound => 'No se encontraron libros';

  @override
  String get noBooksFoundDescription =>
      'Esta biblioteca aún no contiene libros, audiolibros ni cómics.';

  @override
  String bookPercentRead(int percent) {
    return '$percent% leído';
  }

  @override
  String bookTimeLeft(String time) {
    return '$time restante';
  }

  @override
  String get bookHeroRead => 'Leer';

  @override
  String get bookHeroListen => 'Escuchar';

  @override
  String get author => 'Autor';

  @override
  String get unknownAuthor => 'Autor desconocido';

  @override
  String get uncategorized => 'Sin categoría';

  @override
  String get overview => 'Sinopsis';

  @override
  String get noLibrivoxDescription =>
      'Aún no hay descripción de LibriVox para este título.';

  @override
  String get readers => 'Lectores';

  @override
  String get openLinks => 'Abrir enlaces';

  @override
  String get librivoxPage => 'Página de LibriVox';

  @override
  String get internetArchive => 'Internet Archive';

  @override
  String get rssFeed => 'Feed RSS';

  @override
  String get downloadZip => 'Descargar Zip';

  @override
  String sectionCountLabel(int count) {
    return '$count secciones';
  }

  @override
  String firstPublished(int year) {
    return 'Publicado por primera vez en $year';
  }

  @override
  String get noOpenLibraryOverview =>
      'Aún no hay sinopsis disponible de Open Library para este título.';

  @override
  String get subjects => 'Temas';

  @override
  String get all => 'Todos';

  @override
  String booksCount(int count) {
    return '$count libros';
  }

  @override
  String get couldNotLoadSubject =>
      'No se pudo cargar este tema en este momento.';

  @override
  String get audiobookDetails => 'Detalles del audiolibro';

  @override
  String authorsCountTitle(int count) {
    return '$count autores';
  }

  @override
  String audiobookCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count audiolibros',
      one: '1 audiolibro',
    );
    return '$_temp0';
  }

  @override
  String get trackList => 'Lista de pistas';

  @override
  String get itemListPlaceholder => 'La lista de elementos aparecerá aquí';

  @override
  String get failedToLoad => 'Error al cargar';

  @override
  String get delete => 'Eliminar';

  @override
  String get save => 'Guardar';

  @override
  String get moreLikeThis => 'Similares';

  @override
  String get castAndCrew => 'Reparto y equipo';

  @override
  String get collection => 'Colección';

  @override
  String get episodes => 'Episodios';

  @override
  String get nextUp => 'A continuación';

  @override
  String get seasons => 'Temporadas';

  @override
  String get chapters => 'Capítulos';

  @override
  String get features => 'Contenido adicional';

  @override
  String get movies => 'Películas';

  @override
  String get musicVideos => 'Vídeos musicales';

  @override
  String get other => 'Otros';

  @override
  String get discography => 'Discografía';

  @override
  String get similarArtists => 'Artistas similares';

  @override
  String get tableOfContents => 'Índice';

  @override
  String get tracklist => 'Lista de pistas';

  @override
  String discNumber(int number) {
    return 'Disco $number';
  }

  @override
  String get biography => 'Biografía';

  @override
  String get authorDetails => 'Detalles del autor';

  @override
  String get noOverviewAvailable =>
      'Aún no hay sinopsis disponible para este título.';

  @override
  String get noBiographyAvailable =>
      'No hay biografía disponible para este autor.';

  @override
  String get unableToLoadAuthorDetails =>
      'No se pudieron cargar los detalles del autor en este momento.';

  @override
  String published(int year) {
    return 'Publicado en $year';
  }

  @override
  String get publicationDateUnknown => 'Fecha de publicación desconocida';

  @override
  String seasonCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count temporadas',
      one: '1 temporada',
    );
    return '$_temp0';
  }

  @override
  String endsAt(String time) {
    return 'Termina a las $time';
  }

  @override
  String get items => 'Elementos';

  @override
  String get extras => 'Extras';

  @override
  String get additionalParts => 'Partes adicionales';

  @override
  String get behindTheScenes => 'Tras las cámaras';

  @override
  String get deletedScenes => 'Escenas eliminadas';

  @override
  String get featurettes => 'Reportajes';

  @override
  String get interviews => 'Entrevistas';

  @override
  String get scenes => 'Escenas';

  @override
  String get shorts => 'Cortometrajes';

  @override
  String get trailers => 'Tráileres';

  @override
  String timeRemaining(String time) {
    return '$time restante';
  }

  @override
  String endsIn(String time) {
    return 'Termina en $time';
  }

  @override
  String get view => 'Ver';

  @override
  String get resumeReading => 'Continuar leyendo';

  @override
  String get read => 'Leer';

  @override
  String resumeFrom(String position) {
    return 'Reanudar desde $position';
  }

  @override
  String get play => 'Reproducir';

  @override
  String get startOver => 'Empezar de nuevo';

  @override
  String get restart => 'Reiniciar';

  @override
  String get readOffline => 'Leer sin conexión';

  @override
  String get playOffline => 'Reproducir sin conexión';

  @override
  String get audio => 'Audio';

  @override
  String get subtitles => 'Subtítulos';

  @override
  String get version => 'Versión';

  @override
  String get cast => 'Transmitir';

  @override
  String get castMembers => 'Reparto';

  @override
  String get trailer => 'Tráiler';

  @override
  String get finished => 'Terminado';

  @override
  String get favorited => 'En favoritos';

  @override
  String get favorite => 'Favorito';

  @override
  String get playlist => 'Lista de reproducción';

  @override
  String get downloaded => 'Descargado';

  @override
  String get finalizingDownload => 'Terminando…';

  @override
  String get queuedDownload => 'En cola';

  @override
  String queuedMoreCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count más en cola',
      one: '1 más en cola',
    );
    return '$_temp0';
  }

  @override
  String get downloadAll => 'Descargar todo';

  @override
  String get download => 'Descargar';

  @override
  String get deleteDownloaded => 'Eliminar descarga';

  @override
  String get goToSeries => 'Ir a la serie';

  @override
  String get editMetadata => 'Editar metadatos';

  @override
  String get less => 'Menos';

  @override
  String get more => 'Más';

  @override
  String get deleteItem => 'Eliminar elemento';

  @override
  String get deletePlaylist => 'Eliminar lista de reproducción';

  @override
  String get deletePlaylistMessage =>
      '¿Eliminar esta lista de reproducción del servidor?';

  @override
  String get deleteItemMessage => '¿Eliminar este elemento del servidor?';

  @override
  String get failedToDeletePlaylist =>
      'Error al eliminar la lista de reproducción';

  @override
  String get failedToDeleteItem => 'Error al eliminar el elemento';

  @override
  String failedToDeleteItemWithError(String error) {
    return 'La operación de borrado falló con el siguiente error: $error';
  }

  @override
  String get renamePlaylist => 'Renombrar lista de reproducción';

  @override
  String get playlistName => 'Nombre de la lista de reproducción';

  @override
  String get deleteDownloadedAlbum => 'Eliminar álbum descargado';

  @override
  String deleteDownloadedTracksMessage(String title) {
    return '¿Eliminar las pistas descargadas de \"$title\"?';
  }

  @override
  String get downloadedTracksDeleted => 'Pistas descargadas eliminadas';

  @override
  String get downloadedTracksDeleteFailed =>
      'No se pudieron eliminar algunas pistas descargadas';

  @override
  String get noTracksLoaded => 'No hay pistas cargadas';

  @override
  String noItemsLoaded(String itemLabel) {
    return 'No se han cargado $itemLabel';
  }

  @override
  String downloadingTitle(String title, int count) {
    return 'Descargando $title ($count elementos)...';
  }

  @override
  String deleteConfirmMessage(String name) {
    return '¿Seguro que quieres eliminar \"$name\" del servidor? Esta acción no se puede deshacer.';
  }

  @override
  String get itemDeleted => 'Elemento eliminado';

  @override
  String get noPlayableTrailerFound =>
      'No se encontró un tráiler reproducible.';

  @override
  String unsupportedBookFormat(String extension) {
    return 'Formato de libro no admitido: .$extension';
  }

  @override
  String get audioTrack => 'Pista de audio';

  @override
  String get noOtherAudioTracks => 'No hay otras pistas de audio';

  @override
  String get subtitleTrack => 'Pista de subtítulos';

  @override
  String get none => 'Ninguno';

  @override
  String get downloadSubtitlesLabel => 'Descargar subtítulos...';

  @override
  String get searchOpenSubtitlesPlugin => 'Buscar usando OpenSubtitles';

  @override
  String get downloadSubtitles => 'Descargar subtítulos';

  @override
  String get searchingSubtitles => 'Buscando subtítulos…';

  @override
  String get fetchingSubtitles => 'Obteniendo subtítulos';

  @override
  String get downloadingSubtitle => 'Descargando subtítulos…';

  @override
  String get selectedSubtitleInvalid =>
      'El subtítulo seleccionado no es válido.';

  @override
  String subtitleDownloadedSelected(String name) {
    return 'Subtítulo descargado y seleccionado: $name';
  }

  @override
  String get subtitleDownloadedPending =>
      'Subtítulo descargado. Puede tardar un momento en aparecer mientras Jellyfin actualiza el elemento.';

  @override
  String noRemoteSubtitlesFound(String language) {
    return 'No se encontraron subtítulos remotos para $language.';
  }

  @override
  String get selectVersion => 'Seleccionar versión';

  @override
  String versionNumber(int number) {
    return 'Versión $number';
  }

  @override
  String get downloadAllQuality => 'Descargar todo — Calidad';

  @override
  String get downloadQuality => 'Calidad de descarga';

  @override
  String get originalFileNoReencoding => 'Archivo original, sin recodificación';

  @override
  String get originalFilesNoReencoding =>
      'Archivos originales, sin recodificación';

  @override
  String get noEpisodesLoaded => 'No hay episodios cargados';

  @override
  String get downloadScopeTitle => 'Qué descargar';

  @override
  String get downloadAllEpisodes => 'Todos los episodios';

  @override
  String get downloadUnwatchedEpisodes => 'Todos los episodios sin ver';

  @override
  String get downloadAllMovies => 'Todas las películas';

  @override
  String get downloadUnwatchedMovies => 'Todas las películas sin ver';

  @override
  String get downloadScopeLoading => 'Cargando elementos...';

  @override
  String get downloadScopeLoadFailed =>
      'No se pudieron cargar los elementos para descargar';

  @override
  String downloadEstimateTotal(String size) {
    return '~$size en total';
  }

  @override
  String downloadBytesOfTotal(String received, String total) {
    return '$received de $total';
  }

  @override
  String downloadSpeed(String speed) {
    return '$speed/s';
  }

  @override
  String downloadSizeTotal(String size) {
    return '$size en total';
  }

  @override
  String downloadEstimateUnknownCount(int count) {
    return '$count sin estimar';
  }

  @override
  String downloadingItem(String name, String quality) {
    return 'Descargando $name ($quality)...';
  }

  @override
  String get deleteDownloadedFiles => 'Eliminar archivos descargados';

  @override
  String deleteLocalFilesMessage(String typeLabel) {
    return '¿Eliminar los archivos locales de $typeLabel?\n\nSe liberará espacio de almacenamiento. Puedes volver a descargarlos más tarde.';
  }

  @override
  String get downloadedFilesDeleted => 'Archivos descargados eliminados';

  @override
  String get failedToDeleteFiles => 'Error al eliminar archivos';

  @override
  String get deleteFiles => 'Eliminar archivos';

  @override
  String get director => 'DIRECTOR';

  @override
  String get starring => 'PROTAGONISTAS';

  @override
  String get directors => 'DIRECTORES';

  @override
  String get writer => 'GUIONISTA';

  @override
  String get writers => 'GUIONISTAS';

  @override
  String get episodeDirector => 'Director del episodio';

  @override
  String episodeDirectorWithRole(String role) {
    return '$role (director del episodio)';
  }

  @override
  String get episodeWriter => 'Guionista del episodio';

  @override
  String episodeWriterWithRole(String role) {
    return '$role (guionista del episodio)';
  }

  @override
  String get guestStar => 'Estrella invitada';

  @override
  String guestStarWithRole(String role) {
    return '$role (estrella invitada)';
  }

  @override
  String get studio => 'ESTUDIO';

  @override
  String studioMoreCount(int count) {
    return '+$count más';
  }

  @override
  String totalEpisodes(int count) {
    return '$count episodios';
  }

  @override
  String episodeProgress(int watched, int total) {
    return '$watched de $total';
  }

  @override
  String episodeLabel(int number) {
    return 'Episodio $number';
  }

  @override
  String chapterNumber(int number) {
    return 'Capítulo $number';
  }

  @override
  String trackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pistas',
      one: '1 pista',
    );
    return '$_temp0';
  }

  @override
  String chapterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count capítulos',
      one: '1 capítulo',
    );
    return '$_temp0';
  }

  @override
  String born(String date) {
    return 'Nacimiento: $date';
  }

  @override
  String died(String date) {
    return 'Fallecimiento: $date';
  }

  @override
  String age(int age) {
    return 'Edad: $age';
  }

  @override
  String get showLess => 'Mostrar menos';

  @override
  String get readMore => 'Leer más';

  @override
  String get shuffle => 'Aleatorio';

  @override
  String get shuffleAll => 'Mezclar';

  @override
  String get shuffleAllMusic => 'Reproducir toda la música en orden aleatorio';

  @override
  String get carSignInPrompt => 'Inicia sesión en kOS TV desde tu teléfono';

  @override
  String get carServerUnreachable => 'No se puede conectar con tu servidor';

  @override
  String downloadsCount(int count) {
    return '$count descargas';
  }

  @override
  String get perfectMatch => 'Coincidencia perfecta';

  @override
  String get aiTranslated => 'Traducido con IA';

  @override
  String get machineTranslated => 'Traducción automática';

  @override
  String get hearingImpaired => 'SDH';

  @override
  String framerateFps(String rate) {
    return '$rate fps';
  }

  @override
  String get mono => 'Mono';

  @override
  String get stereo => 'Estéreo';

  @override
  String remoteSubtitlePermissionError(String action) {
    return 'Subtítulos remotos ($action): este usuario necesita el permiso de Jellyfin para gestionar subtítulos.';
  }

  @override
  String remoteSubtitleNotFoundError(String action) {
    return 'Subtítulos remotos ($action): no se ha encontrado este elemento en el servidor.';
  }

  @override
  String remoteSubtitleDetailError(String action, String detail) {
    return 'Error en subtítulos remotos ($action): $detail';
  }

  @override
  String remoteSubtitleHttpError(String action, int status) {
    return 'Error en subtítulos remotos ($action) (HTTP $status).';
  }

  @override
  String remoteSubtitleGenericError(String action) {
    return 'Error en subtítulos remotos ($action).';
  }

  @override
  String deleteSeriesFiles(String name) {
    return 'todos los episodios descargados para \"$name\"';
  }

  @override
  String get deleteSeasonFiles =>
      'todos los episodios descargados de esta temporada';

  @override
  String get stillWatching => '¿Sigues viendo?';

  @override
  String get unableToLoadTrailerStream =>
      'No se pudo cargar el stream del tráiler.';

  @override
  String get trailerTimedOut =>
      'El tráiler agotó el tiempo de espera al cargar.';

  @override
  String get playbackFailedForTrailer =>
      'La reproducción falló para este tráiler.';

  @override
  String photoCountOf(int current, int total) {
    return '$current de $total';
  }

  @override
  String get castingUnavailableOffline =>
      'La transmisión no está disponible durante la reproducción sin conexión.';

  @override
  String castActionFailed(String label, String error) {
    return 'Error de $label: $error';
  }

  @override
  String failedToSetCastVolume(String error) {
    return 'No se pudo ajustar el volumen de transmisión: $error';
  }

  @override
  String castControlsTitle(String label) {
    return 'Controles de $label';
  }

  @override
  String get deviceVolume => 'Volumen del dispositivo';

  @override
  String get unavailable => 'No disponible';

  @override
  String get pause => 'Pausa';

  @override
  String get syncPosition => 'Sincronizar posición';

  @override
  String stopCast(String label) {
    return 'Detener $label';
  }

  @override
  String get queueIsEmpty => 'La cola está vacía';

  @override
  String trackNumber(int number) {
    return 'Pista $number';
  }

  @override
  String get remotePlayback => 'Reproducción remota';

  @override
  String get castingToGoogleCast => 'Transmitiendo a Google Cast';

  @override
  String get castingViaAirPlay => 'Transmitiendo vía AirPlay';

  @override
  String get castingViaDlna => 'Transmitiendo vía DLNA';

  @override
  String secondsCount(int seconds) {
    return '$seconds segundos';
  }

  @override
  String get longPressToUnlock => 'Mantén pulsado para desbloquear';

  @override
  String get off => 'Desactivado';

  @override
  String streamTypeFallback(String streamType, int number) {
    return '$streamType $number';
  }

  @override
  String get auto => 'Automático';

  @override
  String bitrateValueMbps(int mbps) {
    return '$mbps Mbps';
  }

  @override
  String get audioDelay => 'Retardo de audio';

  @override
  String delayMinusMs(int value) {
    return '-$value ms';
  }

  @override
  String delayPlusMs(int value) {
    return '+$value ms';
  }

  @override
  String get subtitleDelay => 'Retardo de subtítulos';

  @override
  String get reset => 'Restablecer';

  @override
  String get unknown => 'Desconocido';

  @override
  String get playbackInformation => 'Información de reproducción';

  @override
  String get showMpvStats => 'Mostrar estadísticas de mpv (Mayús+I)';

  @override
  String get hideMpvStats => 'Ocultar estadísticas de mpv (Mayús+I)';

  @override
  String get keyboardShortcutsTitle => 'Atajos de teclado';

  @override
  String get keyboardShortcutsSubtitle =>
      'Teclas para la aplicación, el reproductor y el lector de libros';

  @override
  String get keyboardShortcutsPlayerHint =>
      'Pulsa ? o F1 mientras se reproduce un vídeo para ver esta lista sin salir del reproductor.';

  @override
  String get keyboardShortcutsSectionApp => 'En todas partes';

  @override
  String get keyboardShortcutsSectionAppScope => 'En cualquier pantalla';

  @override
  String get keyboardShortcutsSectionPlayer => 'Reproductor';

  @override
  String get keyboardShortcutsSectionPlayerScope =>
      'Mientras un vídeo esté abierto, reproduciéndose o pausado';

  @override
  String get keyboardShortcutsSectionReader => 'Lector de libros y cómics';

  @override
  String get keyboardShortcutsSectionReaderScope =>
      'Mientras lees un libro o un cómic';

  @override
  String get keyNameArrowKeys => 'Flechas del teclado';

  @override
  String get keyNameSpace => 'Espacio';

  @override
  String get keyNameEnter => 'Intro';

  @override
  String get keyNameEsc => 'Esc';

  @override
  String get keyNameBackspace => 'Borrar';

  @override
  String get keyNameDelete => 'Suprimir';

  @override
  String get keyNamePageUp => 'Re Pág';

  @override
  String get keyNamePageDown => 'Av Pág';

  @override
  String get keyNameHome => 'Inicio';

  @override
  String get keyNameEnd => 'Fin';

  @override
  String get keyNameShift => 'Mayús';

  @override
  String get keyNameCtrl => 'Ctrl';

  @override
  String get keyNameAlt => 'Alt';

  @override
  String get keyNameScrollWheel => 'Rueda del ratón';

  @override
  String get shortcutMoveFocus => 'Moverse entre elementos';

  @override
  String get shortcutActivate => 'Abrir el elemento seleccionado';

  @override
  String get shortcutGoBack => 'Volver atrás';

  @override
  String get shortcutToggleFullscreen =>
      'Activar o desactivar pantalla completa';

  @override
  String get shortcutQuit => 'Cerrar kOS TV';

  @override
  String get shortcutPlayPause => 'Reproducir o pausar';

  @override
  String get shortcutShowControlsOrPlayPause =>
      'Mostrar controles, o reproducir/pausar si los controles son visibles';

  @override
  String get shortcutSeekBack =>
      'Rebobinar (mantener pulsado para saltos más grandes)';

  @override
  String get shortcutSeekForward =>
      'Adelantar (mantener pulsado para saltos más grandes)';

  @override
  String get shortcutVolumeUp => 'Subir volumen';

  @override
  String get shortcutVolumeDown => 'Bajar volumen';

  @override
  String get shortcutMute => 'Silenciar/activar sonido';

  @override
  String get shortcutToggleSubtitles => 'Activar o desactivar subtítulos';

  @override
  String get shortcutSlower => 'Reducir la velocidad';

  @override
  String get shortcutFaster => 'Aumentar la velocidad';

  @override
  String get shortcutPlaybackInfo => 'Mostrar información de reproducción';

  @override
  String get shortcutMpvStats => 'Mostrar u ocultar estadísticas de mpv';

  @override
  String get shortcutRecropBlackBars => 'Volver a recortar las barras negras';

  @override
  String get shortcutLeaveFullscreenOrStop =>
      'Salir de pantalla completa, o detener si no está en pantalla completa';

  @override
  String get shortcutHideControls => 'Ocultar controles';

  @override
  String get shortcutStopPlayback => 'Parar reproducción';

  @override
  String get shortcutNextItem => 'Siguiente elemento';

  @override
  String get shortcutPreviousItem => 'Elemento anterior';

  @override
  String get shortcutSkipSegment =>
      'Saltar la intro o los créditos cuando se ofrezca';

  @override
  String get shortcutShowShortcuts => 'Mostrar esta lista';

  @override
  String get shortcutNextPage => 'Siguiente página';

  @override
  String get shortcutPreviousPage => 'Página anterior';

  @override
  String get shortcutScrollPage => 'Desplazar la página (libros electrónicos)';

  @override
  String get shortcutFirstPage => 'Primera página, o comienzo de capítulo';

  @override
  String get shortcutLastPage => 'Última página o final de capítulo';

  @override
  String get shortcutZoom => 'Acercar/alejar (cómics)';

  @override
  String get shortcutResetZoom => 'Restablecer zoom (cómics)';

  @override
  String get playback => 'Reproducción';

  @override
  String get playMethod => 'Método de reproducción';

  @override
  String get directPlay => 'Reproducción directa';

  @override
  String get directStream => 'Stream directo';

  @override
  String get transcoding => 'Transcodificación';

  @override
  String get transcodeReasons => 'Razones de transcodificación';

  @override
  String get player => 'Reproductor';

  @override
  String get container => 'Contenedor';

  @override
  String get bitrate => 'Tasa de bits';

  @override
  String get video => 'Vídeo';

  @override
  String get resolution => 'Resolución';

  @override
  String get hdr => 'HDR';

  @override
  String get videoRenderer => 'Renderizado de vídeo';

  @override
  String get videoRendererDescription =>
      'Ventana nativa ofrece el movimiento más fluido y envía el HDR a la pantalla sin modificar. Prueba otra opción si el vídeo da problemas.';

  @override
  String get videoRendererNativeWindow => 'Ventana nativa (recomendado)';

  @override
  String get videoRendererNativeHdrOnly => 'Ventana nativa solo para HDR';

  @override
  String get videoRendererInApp => 'En la aplicación (antiguo)';

  @override
  String get track => 'Pista';

  @override
  String get channels => 'Canales';

  @override
  String get format => 'Formato';

  @override
  String get external => 'Externo';

  @override
  String get embedded => 'Incrustado';

  @override
  String castSessionError(String protocol) {
    return 'Error de sesión de $protocol';
  }

  @override
  String failedToLoadBookDetails(String error) {
    return 'No se pudieron cargar los detalles del libro: $error';
  }

  @override
  String get epubUnavailableOnPlatform =>
      'La visualización de EPUB en la app aún no está disponible en esta plataforma.';

  @override
  String get bookReadingUnavailableTitle =>
      'No se pueden leer libros en Apple TV';

  @override
  String get bookReadingUnavailableMessage =>
      'Ábrelo en kOS TV en un teléfono, tablet u ordenador para leerlo. Los audiolibros sí se pueden reproducir aquí.';

  @override
  String formatCannotRenderInApp(String extension) {
    return 'Este formato (.$extension) aún no se puede representar en la aplicación.';
  }

  @override
  String get embeddedRenderingUnavailable =>
      'La visualización de documentos incrustados no está disponible en esta plataforma.';

  @override
  String get couldNotOpenExternalViewer => 'No se pudo abrir el visor externo.';

  @override
  String failedToOpenInAppReader(String error) {
    return 'No se pudo abrir el lector en la aplicación: $error';
  }

  @override
  String bookmarkAlreadySaved(String label) {
    return 'Ya hay un marcador guardado en $label.';
  }

  @override
  String bookmarkAdded(String label) {
    return 'Marcador añadido: $label';
  }

  @override
  String get noBookmarksYet =>
      'Aún no hay marcadores.\nToca el icono de marcador mientras lees para guardar tu posición.';

  @override
  String get noTableOfContentsAvailable => 'No hay índice disponible';

  @override
  String pageLabel(int number) {
    return 'Página $number';
  }

  @override
  String get position => 'Posición';

  @override
  String get bookReader => 'Lector de libros';

  @override
  String formatExtension(String extension) {
    return 'Formato: .$extension';
  }

  @override
  String percentRead(String percent) {
    return '$percent% leído';
  }

  @override
  String get updating => 'Actualizando...';

  @override
  String get markUnread => 'Marcar como no leído';

  @override
  String get markAsRead => 'Marcar como leído';

  @override
  String get reloadReader => 'Recargar lector';

  @override
  String get noPagesFound => 'No se encontraron páginas.';

  @override
  String get failedToDecodePageImage =>
      'Error al decodificar la imagen de la página.';

  @override
  String resetZoom(String zoom) {
    return 'Restablecer zoom (${zoom}x)';
  }

  @override
  String get singlePage => 'Página simple';

  @override
  String get twoPageSpread => 'Doble página';

  @override
  String get addBookmark => 'Añadir marcador';

  @override
  String get bookmarksEllipsis => 'Marcadores...';

  @override
  String get markedAsRead => 'Marcado como leído';

  @override
  String get markedAsUnread => 'Marcado como no leído';

  @override
  String failedToUpdateReadState(String error) {
    return 'No se pudo actualizar el estado de lectura: $error';
  }

  @override
  String get themeSystem => 'Tema: Sistema';

  @override
  String get themeLight => 'Tema: Claro';

  @override
  String get themeDark => 'Tema: Oscuro';

  @override
  String get themeSepia => 'Tema: Sepia';

  @override
  String get invertColorsFixedLayout => 'Invertir colores (diseño fijo)';

  @override
  String get invertColorsPdf => 'Invertir colores (PDF)';

  @override
  String get preparingInAppReader => 'Preparando el lector integrado...';

  @override
  String get pdfDataNotAvailable => 'Datos PDF no disponibles.';

  @override
  String get readerFallbackModeActive => 'Modo alternativo del lector activo';

  @override
  String platformCannotHostDocumentEngine(String extension) {
    return 'Esta plataforma no puede alojar el motor de documentos integrado para archivos $extension.';
  }

  @override
  String get reloadReaderPlatformHint =>
      'Usa Recargar lector después de cambiar a una plataforma compatible (Android, iOS, macOS).';

  @override
  String get openExternally => 'Abrir externamente';

  @override
  String get noEpubChaptersFound => 'No se encontraron capítulos EPUB.';

  @override
  String get readerNotReady => 'El lector no está listo.';

  @override
  String get seriesRecordings => 'Grabaciones de series';

  @override
  String get now => 'Ahora';

  @override
  String get sports => 'Deportes';

  @override
  String get news => 'Noticias';

  @override
  String get kids => 'Infantil';

  @override
  String get premiere => 'Estreno';

  @override
  String get guideRepeatBadge => 'Reposición';

  @override
  String get guideTimeline => 'Línea temporal de la guía';

  @override
  String failedToLoadGuide(String error) {
    return 'No se pudo cargar la guía: $error';
  }

  @override
  String get noChannelsFound => 'No se encontraron canales';

  @override
  String get noProgramData => 'Sin datos de programa';

  @override
  String get liveBadge => 'EN DIRECTO';

  @override
  String get liveTvJumpToLive => 'Ir al directo';

  @override
  String guideNextProgram(String time, String title) {
    return 'Siguiente: $time  $title';
  }

  @override
  String guideMinutesLeft(int minutes) {
    return '$minutes min restantes';
  }

  @override
  String guideHoursLeft(int hours) {
    return '$hours h restantes';
  }

  @override
  String guideHoursMinutesLeft(int hours, int minutes) {
    return '$hours h $minutes min restantes';
  }

  @override
  String get movie => 'Película';

  @override
  String get removedFromFavoriteChannels => 'Eliminado de canales favoritos';

  @override
  String get addedToFavoriteChannels => 'Añadido a canales favoritos';

  @override
  String get failedToUpdateFavoriteChannel =>
      'Error al actualizar el canal favorito';

  @override
  String get unfavoriteChannel => 'Quitar canal de favoritos';

  @override
  String get favoriteChannel => 'Añadir canal a favoritos';

  @override
  String get record => 'Grabar';

  @override
  String nextSeriesRecording(String dateTime) {
    return 'Próxima grabación de la serie: $dateTime';
  }

  @override
  String get noUpcomingSeriesRecording =>
      'La grabación de la serie está programada, pero la guía no tiene próximos episodios';

  @override
  String get seriesRecordingSkipsShowing =>
      'La grabación de la serie se saltará esta emisión';

  @override
  String get seriesRecordingEpisodesQuestion =>
      '¿Qué episodios quieres grabar?';

  @override
  String get seriesRecordingAllEpisodes => 'Todos los episodios';

  @override
  String get seriesRecordingAllEpisodesDescription =>
      'Todas las emisiones, incluidas las reposiciones';

  @override
  String get seriesRecordingNotRecordedEpisodes =>
      'Episodios no grabados anteriormente';

  @override
  String get seriesRecordingNotRecordedEpisodesDescription =>
      'Omite los episodios que ya están en tu biblioteca y graba cada uno una sola vez';

  @override
  String get seriesRecordingNewEpisodesOnly => 'Solo episodios nuevos';

  @override
  String get seriesRecordingNewEpisodesOnlyDescription =>
      'Solo emisiones iniciales, sin repeticiones';

  @override
  String get seriesRecordingSettings => 'Ajustes de la serie';

  @override
  String get seriesRecordingUpdated => 'Grabación de serie actualizada';

  @override
  String get failedToUpdateSeriesRecording =>
      'No es posible actualizar la grabación de la serie';

  @override
  String get recordCurrentEpisode => 'Grabar este episodio';

  @override
  String get recordCurrentProgram => 'Grabar este programa';

  @override
  String get cancelCurrentRecording => 'Cancelar esta grabación';

  @override
  String get cancelRecordingAction => 'Cancelar grabación';

  @override
  String get programSetToRecord => 'Se grabará este programa';

  @override
  String get recordingCancelled => 'Grabación cancelada';

  @override
  String get unableToCreateRecording => 'No se puede crear la grabación';

  @override
  String get recordSeries => 'Grabar serie';

  @override
  String get seriesSetToRecord => 'Se grabará la serie';

  @override
  String get seriesRecordingCancelled => 'Grabación de la serie cancelada';

  @override
  String get unableToCreateSeriesRecording =>
      'No es posible crear una grabación de serie';

  @override
  String get watch => 'Ver';

  @override
  String get watchChannelLive => 'Ver el canal en directo';

  @override
  String get close => 'Cerrar';

  @override
  String failedToPlayChannel(String name) {
    return 'No se pudo reproducir $name';
  }

  @override
  String get playbackStreamLost =>
      'La reproducción se detuvo y no pudo reanudarse.';

  @override
  String get playbackVideoUnsupported =>
      'Este dispositivo no puede reproducir el formato de este vídeo. Prueba con un reproductor externo.';

  @override
  String liveReconnecting(int attempt, int total) {
    return 'Reconectando… ($attempt de $total)';
  }

  @override
  String playerMatchingDisplayRate(String fps) {
    return 'Ajustando la pantalla a $fps fps…';
  }

  @override
  String get failedToLoadRecordings => 'Error al cargar las grabaciones';

  @override
  String get scheduledInNext24Hours => 'Programadas en las próximas 24 horas';

  @override
  String get recentRecordings => 'Grabaciones recientes';

  @override
  String get tvSeries => 'Series de TV';

  @override
  String get failedToLoadSchedule => 'Error al cargar la programación';

  @override
  String get noScheduledRecordings => 'No hay grabaciones programadas';

  @override
  String get cancelRecording => '¿Cancelar grabación?';

  @override
  String cancelScheduledRecordingOf(String name) {
    return '¿Cancelar la grabación programada de \"$name\"?';
  }

  @override
  String get no => 'No';

  @override
  String get yesCancel => 'Sí, cancelar';

  @override
  String get failedToCancelRecording => 'Error al cancelar la grabación';

  @override
  String get failedToLoadSeriesRecordings =>
      'Error al cargar las grabaciones de series';

  @override
  String get noSeriesRecordings => 'No hay grabaciones de series';

  @override
  String get cancelSeriesRecording => 'Cancelar grabación de serie';

  @override
  String get cancelSeriesRecordingQuestion => '¿Cancelar grabación de serie?';

  @override
  String stopRecordingName(String name) {
    return '¿Dejar de grabar \"$name\"?';
  }

  @override
  String get failedToCancelSeriesRecording =>
      'Error al cancelar la grabación de serie';

  @override
  String get searchThisLibrary => 'Buscar en esta biblioteca...';

  @override
  String get searchEllipsis => 'Buscar...';

  @override
  String noResultsForQuery(String query) {
    return 'No hay resultados para \"$query\"';
  }

  @override
  String searchFailedError(String error) {
    return 'La búsqueda falló: $error';
  }

  @override
  String get savedMedia => 'Descargas';

  @override
  String get tvShows => 'Series de TV';

  @override
  String get music => 'Música';

  @override
  String get musicAlbums => 'Álbumes de música';

  @override
  String get noMediaInFilter => 'No hay contenido en este filtro';

  @override
  String get noDownloadedMediaYet => 'Aún no hay contenido descargado';

  @override
  String get browseLibrary => 'Explorar biblioteca';

  @override
  String get deleteDownload => 'Eliminar descarga';

  @override
  String removeItemAndFiles(String name) {
    return '¿Eliminar \"$name\" y sus archivos?';
  }

  @override
  String tracksCount(int count) {
    return '$count pistas';
  }

  @override
  String get album => 'Álbum';

  @override
  String get playAlbum => 'Reproducir álbum';

  @override
  String failedToLoadAlbum(String error) {
    return 'No se pudo cargar el álbum: $error';
  }

  @override
  String noDownloadedTracksForAlbum(String name) {
    return 'No se encontraron pistas descargadas para $name.';
  }

  @override
  String get season => 'Temporada';

  @override
  String get errorLoadingEpisodes => 'Error al cargar los episodios';

  @override
  String get noDownloadedEpisodes => 'No hay episodios descargados';

  @override
  String get deleteEpisode => 'Eliminar episodio';

  @override
  String removeName(String name) {
    return '¿Eliminar \"$name\"?';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String seasonEpisodeLabel(int season, int episode) {
    return 'T$season E$episode';
  }

  @override
  String episodeNumber(int number) {
    return 'Episodio $number';
  }

  @override
  String get seriesNotFound => 'Serie no encontrada';

  @override
  String get errorLoadingSeries => 'Error al cargar la serie';

  @override
  String get downloadedEpisodes => 'Episodios descargados';

  @override
  String seasonNumber(int number) {
    return 'Temporada $number';
  }

  @override
  String get specials => 'Especiales';

  @override
  String get deleteSeason => 'Eliminar temporada';

  @override
  String deleteAllEpisodesInSeason(String season) {
    return '¿Eliminar todos los episodios descargados de $season?';
  }

  @override
  String episodeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodios',
      one: '1 episodio',
    );
    return '$_temp0';
  }

  @override
  String get storageManagement => 'Gestión de almacenamiento';

  @override
  String get storageBreakdown => 'Desglose de almacenamiento';

  @override
  String get downloadedItems => 'Elementos descargados';

  @override
  String get activeDownloads => 'Descargas activas';

  @override
  String savedMediaCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos',
      one: '1 elemento',
    );
    return '$_temp0';
  }

  @override
  String savedMediaOfLimit(String used, String limit) {
    return '$used de $limit';
  }

  @override
  String get savedMediaSelectItems => 'Seleccionar elementos';

  @override
  String get savedMediaNoDownloads => 'Aún no hay nada guardado';

  @override
  String get savedMediaNoDownloadsDetail =>
      'Las descargas que inicies aparecerán aquí y se podrán reproducir sin conexión.';

  @override
  String get savedMediaNoActiveDownloads =>
      'No se está descargando nada en este momento';

  @override
  String get savedMediaNoResults =>
      'No hay descargas que coincidan con esa búsqueda';

  @override
  String get savedMediaPlayFromStart => 'Reproducir desde el principio';

  @override
  String get savedMediaGoToDetails => 'Ir a los detalles';

  @override
  String get savedMediaDeleteDownload => 'Eliminar descarga';

  @override
  String savedMediaDeleteSeason(String season) {
    return 'Eliminar $season';
  }

  @override
  String savedMediaDeleteEpisodes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Eliminar $count episodios',
      one: 'Eliminar 1 episodio',
    );
    return '$_temp0';
  }

  @override
  String get savedMediaOpenShow => 'Abrir serie';

  @override
  String get savedMediaPlayNextUnwatched => 'Reproducir siguiente no visto';

  @override
  String get savedMediaRead => 'Leer';

  @override
  String get savedMediaCancelDownload => 'Cancelar descarga';

  @override
  String get sortBySize => 'Tamaño';

  @override
  String get sortByName => 'Nombre';

  @override
  String get sortByDateAdded => 'Fecha de adición';

  @override
  String get storageLimit => 'Límite de almacenamiento';

  @override
  String get noLimit => 'Sin límite';

  @override
  String get deleteAllDownloads => 'Eliminar todas las descargas';

  @override
  String get deleteAllDownloadsWarning =>
      'Esto eliminará todos los archivos multimedia descargados y no se puede deshacer.';

  @override
  String get deleteAll => 'Eliminar todo';

  @override
  String get deleteSelected => 'Eliminar seleccionados';

  @override
  String deleteSelectedCount(int count) {
    return '¿Eliminar $count elementos descargados?';
  }

  @override
  String get musicAndAudiobooks => 'Música y audiolibros';

  @override
  String get images => 'Imágenes';

  @override
  String get database => 'Base de datos';

  @override
  String ofStorageLimit(String limit) {
    return 'de un límite de $limit';
  }

  @override
  String get settings => 'Ajustes';

  @override
  String get settingsSearchHint => 'Buscar ajustes';

  @override
  String get authentication => 'Autenticación';

  @override
  String get autoLoginServerManagement =>
      'Inicio de sesión automático, gestión de servidores';

  @override
  String get pinCode => 'Código PIN';

  @override
  String get setUpPinCodeProtection => 'Configurar protección con código PIN';

  @override
  String get parentalControls => 'Control parental';

  @override
  String get contentRatingRestrictions =>
      'Restricciones de clasificación de contenido';

  @override
  String get bitRateResolutionBehavior =>
      'Tasa de bits, resolución, comportamiento';

  @override
  String get languageSizeAppearance => 'Idioma, tamaño, apariencia';

  @override
  String get qualityStorage => 'Calidad, almacenamiento';

  @override
  String get switchServer => 'Cambiar de servidor';

  @override
  String get signOut => 'Cerrar sesión';

  @override
  String get versionLicenses => 'Versión, licencias';

  @override
  String get account => 'Cuenta';

  @override
  String get signInAndSecurity => 'Inicio de sesión y seguridad';

  @override
  String get administration => 'Administración';

  @override
  String get serverSettingsUsersLibraries =>
      'Ajustes del servidor, usuarios, bibliotecas';

  @override
  String get customization => 'Personalización';

  @override
  String get themeAndLayout => 'Tema y diseño';

  @override
  String get videoAndSubtitles => 'Vídeo y subtítulos';

  @override
  String get pluginAndRequests => 'Complemento y solicitudes';

  @override
  String get customizeAccountPlaybackInterface =>
      'Personalizar cuenta, reproducción e interfaz';

  @override
  String optionsCount(int count) {
    return '$count opciones';
  }

  @override
  String get themeAndAppearance => 'Tema y apariencia';

  @override
  String get focusBorderColor => 'Color del borde de enfoque';

  @override
  String get watchedIndicators => 'Indicadores de visto';

  @override
  String get showPosterLabels => 'Etiquetas en los pósteres';

  @override
  String get showPosterLabelsSubtitle =>
      'Muestra las etiquetas en los pósteres, como 4K o HDR.';

  @override
  String get always => 'Siempre';

  @override
  String get mixedRowsOnly => 'Solo filas mixtas';

  @override
  String get hideUnwatched => 'Ocultar no vistos';

  @override
  String get episodesOnly => 'Solo episodios';

  @override
  String get never => 'Nunca';

  @override
  String get focusExpansionAnimation => 'Animación de expansión al enfocar';

  @override
  String get desktopUiScale => 'Escala de la interfaz';

  @override
  String get scaleFocusedCards =>
      'Agrandar las tarjetas enfocadas o bajo el cursor';

  @override
  String get seriesThumbnails => 'Miniaturas de series';

  @override
  String get seriesThumbnailsDescription =>
      'En las series, usa la imagen principal de la serie en lugar de la miniatura del episodio.';

  @override
  String get homeRowInfoOverlay =>
      'Superposición de información en filas del inicio';

  @override
  String get showTitleMetadataOnHomeRows =>
      'Mostrar título y metadatos en las filas del inicio';

  @override
  String get clockDisplay => 'Visualización del reloj';

  @override
  String get inMenus => 'En los menús';

  @override
  String get inVideo => 'En el vídeo';

  @override
  String get seasonalEffects => 'Efectos estacionales';

  @override
  String get seasonalEffectsDescription =>
      'Efectos visuales y decoraciones de temporada';

  @override
  String get loadingAnimation => 'Animación de carga';

  @override
  String get loadingAnimationDescription =>
      'Personaliza las animaciones de carga de kOS TV';

  @override
  String get loadingAnimationConfiguration =>
      'Configuración de la animación de carga';

  @override
  String get loadingAnimationImage => 'Imagen';

  @override
  String get loadingAnimationImageMoonfinLogo => 'Logo de kOS TV';

  @override
  String get loadingAnimationImageSpinner => 'Indicador giratorio';

  @override
  String get loadingAnimationImageRunner => 'Corredor';

  @override
  String get loadingAnimationImageMoonPhases => 'Fases lunares';

  @override
  String get loadingAnimationImageMoonfinPhases => 'Fases de kOS TV';

  @override
  String get loadingAnimationImageNeonfinPhases => 'Fases de neón';

  @override
  String get loadingAnimationSize => 'Tamaño de la animación';

  @override
  String get loadingAnimationSizeThumbnail => 'Miniatura';

  @override
  String get loadingAnimationSizeSmall => 'Pequeño';

  @override
  String get loadingAnimationSizeMedium => 'Mediano';

  @override
  String get loadingAnimationSizeLarge => 'Grande';

  @override
  String get loadingAnimationPosition => 'Posición de la animación';

  @override
  String get loadingAnimationPositionTopLeft => 'Arriba a la izquierda';

  @override
  String get loadingAnimationPositionTopCenter => 'Arriba en el centro';

  @override
  String get loadingAnimationPositionTopRight => 'Arriba a la derecha';

  @override
  String get loadingAnimationPositionMiddleLeft => 'Centro a la izquierda';

  @override
  String get loadingAnimationPositionMiddle => 'Centro';

  @override
  String get loadingAnimationPositionMiddleRight => 'Centro a la derecha';

  @override
  String get loadingAnimationPositionBottomLeft => 'Abajo a la izquierda';

  @override
  String get loadingAnimationPositionBottomCenter => 'Abajo en el centro';

  @override
  String get loadingAnimationPositionBottomRight => 'Abajo a la derecha';

  @override
  String get loadingAnimationPositionBouncing => 'Rebotando';

  @override
  String get loadingAnimationSpeed => 'Velocidad de la animación';

  @override
  String get loadingAnimationSpeedSlow => 'Lenta';

  @override
  String get loadingAnimationSpeedModerate => 'Moderada';

  @override
  String get loadingAnimationSpeedFast => 'Rápida';

  @override
  String get loadingAnimationSpeedUltra => 'Ultra';

  @override
  String get showLoadingAnimationText => 'Mostrar texto';

  @override
  String get loadingAnimationPreview => 'Vista previa';

  @override
  String get snow => 'Nieve';

  @override
  String get fireworks => 'Fuegos artificiales';

  @override
  String get confetti => 'Confeti';

  @override
  String get fallingLeaves => 'Hojas cayendo';

  @override
  String get seasonalChristmas => 'Navidad';

  @override
  String get seasonalPetals => 'Pétalos de primavera';

  @override
  String get seasonalFireflies => 'Luciérnagas';

  @override
  String get seasonalHalloween => 'Halloween';

  @override
  String get seasonalDensity => 'Densidad';

  @override
  String get seasonalDensityLight => 'Baja';

  @override
  String get seasonalDensityNormal => 'Normal';

  @override
  String get seasonalDensityHeavy => 'Alta';

  @override
  String get seasonalFollower => 'Pieza que sigue la selección';

  @override
  String get seasonalFollowerDescription =>
      'Una pieza festiva, como la plancheta de ouija de Halloween, sigue lo que seleccionas en Inicio';

  @override
  String get seasonalFollowerPointerDescription =>
      'Una pieza festiva, como la plancheta de ouija de Halloween, sustituye al puntero del ratón en Inicio';

  @override
  String get seasonalRow => 'Fila de temporada';

  @override
  String get seasonalRowDescription =>
      'Muestra una fila de películas festivas de tu biblioteca.';

  @override
  String get seasonalRowSubtitle => 'De temporada';

  @override
  String get seasonalRowCountry => 'País';

  @override
  String get seasonalRowCountryAuto => 'Automático';

  @override
  String get countryUnitedStates => 'Estados Unidos';

  @override
  String get countryCanada => 'Canadá';

  @override
  String get seasonalRowCountryOther => 'Otro';

  @override
  String get seasonalRowHolidays => 'Festividades';

  @override
  String get seasonalRowHolidaysHint =>
      'Desmarca una festividad para ocultar su fila.';

  @override
  String get seasonalRowAllYear => 'Mostrar todo el año';

  @override
  String get seasonalRowAllYearDescription =>
      'Muestra una fila festiva también fuera de las fechas señaladas, cada día de una festividad marcada distinta.';

  @override
  String get holidayNewYear => 'Año Nuevo';

  @override
  String get holidayValentines => 'San Valentín';

  @override
  String get holidayEaster => 'Semana Santa';

  @override
  String get holidayPride => 'Orgullo';

  @override
  String get holidayHalloween => 'Halloween';

  @override
  String get holidayThanksgiving => 'Acción de Gracias';

  @override
  String get holidayChristmas => 'Películas de Navidad';

  @override
  String get holidayLunarNewYear => 'Año Nuevo Lunar';

  @override
  String get holidayDiwali => 'Diwali';

  @override
  String get themeMusic => 'Música de tema';

  @override
  String get playThemeMusicOnDetailPages =>
      'Reproducir música de tema en páginas de detalles';

  @override
  String get themeMusicVolume => 'Volumen de la música de tema';

  @override
  String percentValue(int value) {
    return '$value %';
  }

  @override
  String get themeMusicOnHomeRows => 'Música de tema en filas del inicio';

  @override
  String get playWhenBrowsingHomeScreen =>
      'Reproducir al navegar por la pantalla de inicio';

  @override
  String get loopThemeMusic => 'Repetir música de tema';

  @override
  String get loopThemeMusicSubtitle =>
      'Repetir la pista en lugar de reproducirla una vez';

  @override
  String get detailsBackgroundBlur => 'Desenfoque de fondo en detalles';

  @override
  String get detailsBackgroundOpacity => 'Opacidad del fondo';

  @override
  String pixelValue(int value) {
    return '$value px';
  }

  @override
  String get browsingBackgroundBlur => 'Desenfoque de fondo al navegar';

  @override
  String get maxStreamingBitrate => 'Tasa de bits máxima de streaming';

  @override
  String get maxResolution => 'Resolución máxima';

  @override
  String get playerZoomMode => 'Modo de zoom del reproductor';

  @override
  String get settingsScrollWheelAction => 'Rueda del ratón';

  @override
  String get settingsScrollWheelActionDescription =>
      'Elige qué hace la rueda del ratón al desplazarse sobre el vídeo durante la reproducción.';

  @override
  String get scrollWheelActionOff => 'Desactivado';

  @override
  String get scrollWheelActionSeek => 'Avanzar o retroceder';

  @override
  String get scrollWheelActionVolume => 'Volumen';

  @override
  String get playerTooltipVolume => 'Volumen';

  @override
  String get fit => 'Ajustar';

  @override
  String get autoCrop => 'Ampliar hasta llenar';

  @override
  String get cropBlackBars => 'Recortar bandas negras';

  @override
  String get settingsCropBlackBarsDescription =>
      'Detecta las bandas negras grabadas en el vídeo al empezar la reproducción, las recorta y llena la pantalla. Puedes volver a recortar desde el botón de zoom del reproductor.';

  @override
  String get cropBlackBarsRecropInterval => 'Intervalo de recorte';

  @override
  String get cropBlackBarsOnce => 'Una vez al empezar';

  @override
  String get cropBlackBarsEverySecond => 'Cada segundo';

  @override
  String get settingsCropBlackBarsIntervalDescription =>
      'Sigue los cambios de relación de aspecto durante la reproducción.';

  @override
  String get playerRecroppingBlackBars =>
      'Recortando de nuevo las bandas negras';

  @override
  String get stretch => 'Estirar';

  @override
  String get refreshRateSwitching => 'Cambio de frecuencia de actualización';

  @override
  String get disabled => 'Desactivado';

  @override
  String get manual => 'Manual';

  @override
  String get autoDetect => 'Detección automática';

  @override
  String get scaleOnTv => 'Escalar en TV';

  @override
  String get scaleOnDevice => 'Escalar en dispositivo';

  @override
  String get trickPlay => 'Trickplay';

  @override
  String get showPreviewThumbnailsWhenSeeking =>
      'Mostrar miniaturas al avanzar o retroceder';

  @override
  String get trickplayDisplayStyleSingle => 'Miniatura única';

  @override
  String get trickplayDisplayStyleStrip => 'Tira de fotogramas';

  @override
  String get trickplayModeFull => 'Pantalla completa';

  @override
  String get trickplaySettingsPreviewHint =>
      'Mueve el deslizador para ver cómo queda la vista previa';

  @override
  String get trickplayPreviewScale => 'Tamaño de la vista previa';

  @override
  String get trickplayVerticalOffset => 'Distancia a la barra de progreso';

  @override
  String get trickplayFollowScrubPosition => 'Seguir la posición de búsqueda';

  @override
  String get trickplayFollowScrubPositionSubtitle =>
      'La vista previa se desliza por la barra de progreso mientras buscas, en vez de quedarse centrada';

  @override
  String get trickplayPauseWhileScrubbing => 'Pausar mientras buscas';

  @override
  String get trickplayPauseWhileScrubbingSubtitle =>
      'La reproducción se pausa mientras buscas y se reanuda al pulsar reproducir. Desactívalo para seguir reproduciendo y saltar directamente al nuevo punto';

  @override
  String get showDescriptionOnPause => 'Mostrar descripción al pausar';

  @override
  String get dimVideoShowOverview =>
      'Atenuar el vídeo y mostrar la sinopsis en pausa';

  @override
  String get showChapterMarkers => 'Marcas de capítulos';

  @override
  String get showChapterMarkersDescription =>
      'Marca dónde empieza cada capítulo en la barra de progreso';

  @override
  String get osdLockButton => 'Botón de bloqueo del OSD';

  @override
  String get osdLockButtonDescription =>
      'Muestra un botón de bloqueo que ignora los toques hasta que lo mantienes pulsado';

  @override
  String get playerSwipeGestures => 'Deslizar para volumen y brillo';

  @override
  String get playerSwipeGesturesDescription =>
      'Desliza hacia arriba o hacia abajo en el reproductor para cambiar el brillo a la izquierda y el volumen a la derecha';

  @override
  String get invertGestureIndicators => 'Invertir indicadores de gestos';

  @override
  String get invertGestureIndicatorsDescription =>
      'Coloca los indicadores de brillo y volumen en el mismo lado en que deslizas o en el contrario';

  @override
  String get gestureIndicatorSame => 'Mismo lado';

  @override
  String get gestureIndicatorInverted => 'Lado contrario';

  @override
  String get osdButtons => 'Botones del reproductor';

  @override
  String get osdButtonsDescription =>
      'Elige qué botones muestra el reproductor';

  @override
  String get osdButtonsSectionDescription =>
      'Los controles de reproducción se muestran siempre. Todo lo demás lo decides tú, y cada tipo de dispositivo guarda su propia lista.';

  @override
  String get detailButtons => 'Botones de acción';

  @override
  String get detailButtonsDescription =>
      'Elige qué botones muestra la pantalla de detalles';

  @override
  String get detailButtonsSectionDescription =>
      'Reproducir va siempre primero y los botones bloqueados se muestran siempre. Todo lo demás lo decides tú, y cada tipo de dispositivo guarda su propia lista.';

  @override
  String get actionButtonsOnScreen => 'Botones de acción en pantalla';

  @override
  String get actionButtonsOnScreenDescription =>
      'Elige cuántos botones de acción aparecen antes de pasar al menú Más acciones.';

  @override
  String get actionButtonsOnScreenAuto => 'Automático (según el tema)';

  @override
  String get actionButtonsOnScreenPlayOnly => '1 (solo Reproducir)';

  @override
  String get actionButtonsOnScreenAll => 'Todos (desplazamiento horizontal)';

  @override
  String get detailMetadata => 'Fila de metadatos';

  @override
  String get detailMetadataDescription =>
      'Elige y ordena los metadatos que muestra la pantalla de detalles';

  @override
  String get detailMetadataSectionDescription =>
      'Activa o desactiva cada dato y ordena cómo aparecen en la pantalla de detalles. Cada tipo de dispositivo guarda su propia lista.';

  @override
  String get detailMetadataYear => 'Año de estreno';

  @override
  String get detailMetadataParentalRating => 'Clasificación por edades';

  @override
  String get detailMetadataRuntimeAndSeasons => 'Duración y temporadas';

  @override
  String get detailMetadataStatus => 'Estado de la serie';

  @override
  String get detailMetadataStatusSubtitle =>
      'Indica si la serie continúa, ha terminado o va a volver';

  @override
  String get detailMetadataGenres => 'Géneros';

  @override
  String get detailMetadataUpcomingEpisodeDate => 'Próximos episodios';

  @override
  String get detailMetadataUpcomingEpisodeDateSubtitle =>
      'Usa Sonarr y TMDB para mostrar las próximas fechas de estreno';

  @override
  String get detailSections => 'Secciones';

  @override
  String get detailSectionsDescription =>
      'Elige qué partes de la pantalla de detalles se muestran';

  @override
  String get detailSectionsScreenDescription =>
      'Solo aparecen las secciones que puede mostrar el estilo actual de la pantalla de detalles. Si ocultas una, se oculta en todos los estilos que la tienen.';

  @override
  String get detailSectionGroupHeader => 'Cabecera';

  @override
  String get detailSectionGroupSections => 'Secciones';

  @override
  String get detailSectionGroupPerson => 'Páginas de personas';

  @override
  String get detailSectionGroupCollection => 'Páginas de colecciones';

  @override
  String get detailSectionGroupOther => 'Otras';

  @override
  String get detailSectionLogo => 'Logotipo';

  @override
  String get detailSectionLogoSubtitle =>
      'Si está desactivado, el título se muestra como texto';

  @override
  String get detailSectionTagline => 'Eslogan';

  @override
  String get detailSectionPoster => 'Póster';

  @override
  String get detailSectionVersionBadge => 'Insignia de versión';

  @override
  String get detailSectionUpNext => 'A continuación';

  @override
  String get detailSectionLyrics => 'Letra';

  @override
  String get detailSectionCast => 'Reparto';

  @override
  String get detailSectionCastSubtitle =>
      'También en las páginas de colecciones';

  @override
  String get detailSectionCrew => 'Dirección y guion';

  @override
  String get detailSectionStudios => 'Estudios';

  @override
  String get detailSectionChapters => 'Capítulos';

  @override
  String get detailSectionExtras => 'Extras';

  @override
  String get detailSectionCollections => 'Colecciones';

  @override
  String get detailSectionMoreLikeThis => 'Más como esto';

  @override
  String get detailSectionMoreLikeThisSubtitle =>
      'También álbumes y artistas parecidos';

  @override
  String get detailSectionMoreEpisodes => 'Más episodios';

  @override
  String get detailSectionMoreEpisodesSubtitle => 'En las páginas de episodios';

  @override
  String get detailSectionMediaInfo => 'Información multimedia';

  @override
  String get detailSectionMediaInfoSubtitle =>
      'Archivo, pistas y comprobación de reproducción directa';

  @override
  String get detailSectionBiography => 'Biografía';

  @override
  String get detailSectionBirthplace => 'Lugar de nacimiento';

  @override
  String get detailSectionPersonLinks => 'Enlaces';

  @override
  String get detailSectionPersonLinksSubtitle => 'IMDb, TMDB y redes sociales';

  @override
  String get detailSectionGuestAppearances => 'Apariciones como invitado';

  @override
  String get detailSectionMusicVideos => 'Videoclips';

  @override
  String get detailSectionPlaylistOrder => 'Orden de la lista de reproducción';

  @override
  String get detailSectionBookGenres => 'Géneros del libro';

  @override
  String get detailSectionPhotoExif => 'Detalles de la foto';

  @override
  String upcomingEpisodeNext(String date, int season, int episode) {
    return 'Próximo: $date (T$season:E$episode)';
  }

  @override
  String get upcomingEpisodeToday => 'Hoy';

  @override
  String get upcomingEpisodeTomorrow => 'Mañana';

  @override
  String get radarrCalendarRow => 'Próximas películas (Radarr)';

  @override
  String get sonarrCalendarRow => 'Próximas series (Sonarr)';

  @override
  String get mergedCalendarRow => 'Próximos estrenos';

  @override
  String get arrCalendarsRowSubtitle => 'Calendarios de Radarr y Sonarr';

  @override
  String get radarrCalendarRowSubtitle => 'Calendario de Radarr';

  @override
  String get sonarrCalendarRowSubtitle => 'Calendario de Sonarr';

  @override
  String calendarReleaseIn(int days, String date) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Dentro de $days días',
      one: 'Mañana',
      zero: 'Hoy',
    );
    return '$_temp0 ($date)';
  }

  @override
  String get calendarReleaseCinema => 'Cine';

  @override
  String get calendarReleaseDigital => 'Digital';

  @override
  String get calendarReleasePhysical => 'Físico';

  @override
  String get upcomingCalendars => 'Calendarios de estrenos';

  @override
  String get upcomingCalendarsDescription =>
      'Activa o desactiva los calendarios de estrenos de Radarr/Sonarr.';

  @override
  String get enableRadarrCalendar =>
      'Activar el calendario de estrenos de Radarr';

  @override
  String get radarrCalendarShowCinema => 'Mostrar próximos estrenos en cines';

  @override
  String get radarrCalendarShowDigital => 'Mostrar próximos estrenos digitales';

  @override
  String get radarrCalendarShowPhysical =>
      'Mostrar próximos lanzamientos en formato físico';

  @override
  String get calendarShowReleaseDate => 'Mostrar la fecha de estreno en Inicio';

  @override
  String get radarrCalendarHideDownloaded =>
      'Ocultar películas que ya están en el servidor';

  @override
  String get enableSonarrCalendar =>
      'Activar el calendario de estrenos de Sonarr';

  @override
  String get sonarrCalendarShowEpisodeInfo =>
      'Mostrar información del episodio';

  @override
  String get sonarrCalendarHideDownloaded =>
      'Ocultar episodios que ya están en el servidor';

  @override
  String get mergeRadarrSonarrCalendars =>
      'Unir los calendarios de Sonarr y Radarr';

  @override
  String get moveUp => 'Subir';

  @override
  String get moveDown => 'Bajar';

  @override
  String get buttonOrderHint =>
      'Usa las flechas para cambiar el orden. Con el mando, izquierda y derecha mueven el botón resaltado. Si desactivas uno, pasa debajo de los demás.';

  @override
  String get buttonShownInSyncPlayGroup =>
      'Solo aparece cuando estás en una sala de Ver juntos';

  @override
  String get orientationLock => 'Bloquear orientación';

  @override
  String get fullscreen => 'Pantalla completa';

  @override
  String get audioBehavior => 'Comportamiento de audio';

  @override
  String get downmixToStereo => 'Mezclar a estéreo';

  @override
  String get defaultAudioLanguage => 'Idioma de audio predeterminado';

  @override
  String get fallbackAudioLanguage => 'Idioma de audio alternativo';

  @override
  String get preferDefaultAudioTrack =>
      'Preferir pista de audio predeterminada';

  @override
  String get preferDefaultAudioTrackDescription =>
      'Preferir la pista de audio original en lugar del doblaje localizado.';

  @override
  String get preferAudioDescription => 'Preferir pistas de audiodescripción';

  @override
  String get preferAudioDescriptionDescription =>
      'Preferir las pistas de audiodescripción en lugar de las normales.';

  @override
  String get autoServerDefault => 'Automático (predeterminado del servidor)';

  @override
  String get spanish => 'Español';

  @override
  String get french => 'Francés';

  @override
  String get german => 'Alemán';

  @override
  String get italian => 'Italiano';

  @override
  String get portuguese => 'Portugués';

  @override
  String get japanese => 'Japonés';

  @override
  String get korean => 'Coreano';

  @override
  String get chinese => 'Chino';

  @override
  String get russian => 'Ruso';

  @override
  String get arabic => 'Árabe';

  @override
  String get hindi => 'Hindi';

  @override
  String get dutch => 'Neerlandés';

  @override
  String get swedish => 'Sueco';

  @override
  String get norwegian => 'Noruego';

  @override
  String get danish => 'Danés';

  @override
  String get finnish => 'Finés';

  @override
  String get polish => 'Polaco';

  @override
  String get ac3Passthrough => 'Passthrough AC3';

  @override
  String get dtsPassthrough => 'Passthrough DTS';

  @override
  String get trueHdSupport => 'Compatibilidad con TrueHD';

  @override
  String get enableDtsPassthrough =>
      'Envía el audio DTS en bitstream solo al receptor AV; requiere un receptor compatible y una pista de origen DTS';

  @override
  String get settingsAudioFallbackCodec => 'Códec de reserva de audio';

  @override
  String get settingsAudioFallbackCodecDescription =>
      'Selecciona el formato de destino para transcodificar el audio multicanal cuando el flujo de origen no se puede reproducir directamente ni enviar por passthrough.';

  @override
  String get transcodeAudioCodecs => 'Códecs de audio que se transcodifican';

  @override
  String get transcodeAudioCodecsDescription =>
      'El servidor convierte el audio en estos formatos en lugar de enviarlo tal cual.';

  @override
  String get settingsAudioFallbackCodecAuto =>
      'Detección automática\n(Recomendado)';

  @override
  String get settingsAudioFallbackCodecAac => 'AAC\n(Predeterminado)';

  @override
  String get settingsAudioFallbackCodecAc3 => 'AC3\n(Dolby Digital)';

  @override
  String get settingsAudioFallbackCodecEac3 => 'EAC3\n(Dolby Digital Plus)';

  @override
  String get settingsAudioFallbackCodecMp3 => 'MP3\n(Solo estéreo)';

  @override
  String get settingsAudioFallbackCodecOpus => 'Opus\n(Eficiente)';

  @override
  String get settingsAudioFallbackCodecFlac => 'FLAC\n(Sin pérdida)';

  @override
  String get settingsMaxAudioChannels => 'Canales de audio máximos';

  @override
  String get settingsMaxAudioChannelsDescription =>
      'Configura el número máximo de canales de tu equipo de audio. Los flujos multicanal que superen este límite se mezclarán o se transcodificarán.';

  @override
  String get settingsMaxAudioChannelsAuto =>
      'Detección automática\n(Predeterminado del hardware)';

  @override
  String get settingsMaxAudioChannelsMono => '1.0 Mono';

  @override
  String get settingsMaxAudioChannelsStereo => '2.0 Estéreo';

  @override
  String get settingsMaxAudioChannels3_0 => '3.0 / 2.1 Envolvente';

  @override
  String get settingsMaxAudioChannels4_0 => '4.0 / 3.1 Cuadrafónico';

  @override
  String get settingsMaxAudioChannels5_0 => '5.0 / 4.1 Envolvente';

  @override
  String get settingsMaxAudioChannels5_1 => '5.1 Envolvente';

  @override
  String get settingsMaxAudioChannels6_1 => '6.1 Envolvente';

  @override
  String get settingsMaxAudioChannels7_1 => '7.1 Envolvente';

  @override
  String get settingsAudioPassthroughAdvanced => 'Passthrough (avanzado)';

  @override
  String get settingsAudioCodecPassthrough => 'Passthrough de códecs';

  @override
  String get settingsAudioCodecPassthroughDescription =>
      'Activa solo los formatos que admita tu receptor AV o dispositivo HDMI.';

  @override
  String get settingsAudioEac3Passthrough => 'Passthrough EAC3';

  @override
  String get settingsAudioDtsCorePassthrough => 'Passthrough DTS Core';

  @override
  String get settingsAudioDtsHdPassthrough => 'Passthrough DTS-HD MA';

  @override
  String get settingsAudioPassthroughMode => 'Passthrough';

  @override
  String get settingsAudioPassthroughModeDescription =>
      'Cómo llega el sonido envolvente comprimido a tu tele o a tu receptor.';

  @override
  String get settingsAudioPassthroughModeDisabled =>
      'Desactivado (decodificar siempre en este dispositivo)';

  @override
  String get settingsAudioPassthroughModeAuto =>
      'Automático (según lo que admita el dispositivo detectado)';

  @override
  String get settingsAudioPassthroughModeManual =>
      'Manual (elige los formatos abajo)';

  @override
  String get settingsAudioPassthroughOutput => 'Salida passthrough';

  @override
  String get settingsAudioPassthroughOutputDescription =>
      'Quién empaqueta el flujo de bits para la conexión HDMI. Prueba el empaquetador de la app si el passthrough no suena o falla en este dispositivo.';

  @override
  String get settingsAudioPassthroughOutputPlatform =>
      'Automático, empaquetador del sistema (AudioTrack RAW)';

  @override
  String get settingsAudioPassthroughOutputIec =>
      'Empaquetador de la app (AudioTrack IEC)';

  @override
  String get settingsAudioPassthroughOutputIecLabel => 'App (IEC)';

  @override
  String get settingsDownmixToStereoDescription =>
      'Mezcla todo el audio decodificado en dos canales.';

  @override
  String get settingsAudioEac3IncludesAtmos =>
      'Envía E-AC-3 sin decodificar (bitstream), incluido Dolby Atmos (JOC).';

  @override
  String get settingsAudioDtsHdIncludesDtsX =>
      'Envía DTS-HD sin decodificar (bitstream), incluido DTS:X.';

  @override
  String get settingsAudioTrueHdIncludesAtmos =>
      'Envía TrueHD sin decodificar (bitstream), incluido Dolby Atmos.';

  @override
  String get settingsAudioTrueHdPassthrough => 'Passthrough TrueHD';

  @override
  String get settingsDetectedAudioCapabilities =>
      'Capacidades de audio detectadas';

  @override
  String get settingsDetectedAudioCapabilitiesUnavailable =>
      'Aún no se han detectado las capacidades de audio.';

  @override
  String get settingsAudioRouteLabel => 'Ruta';

  @override
  String get settingsAudioDecodeLabel => 'Decodificación';

  @override
  String get settingsAudioPassthroughLabel => 'Passthrough';

  @override
  String get settingsAudioHdRoute => 'Ruta de audio HD';

  @override
  String get settingsAudioRouteHdmi => 'HDMI';

  @override
  String get settingsAudioRouteArc => 'ARC';

  @override
  String get settingsAudioRouteEarc => 'eARC';

  @override
  String get settingsAudioRouteBluetooth => 'Bluetooth';

  @override
  String get settingsAudioRouteSpeaker => 'Altavoz';

  @override
  String get settingsAudioRouteHeadphones => 'Auriculares';

  @override
  String settingsAudioPcmChannels(int count) {
    return 'PCM de $count canales';
  }

  @override
  String get nightMode => 'Modo nocturno';

  @override
  String get compressDynamicRange => 'Comprimir rango dinámico';

  @override
  String get advancedMpv => 'Ajustes avanzados de mpv';

  @override
  String get enableCustomMpvConf => 'Usar mpv.conf personalizado';

  @override
  String get applyMpvConfBeforePlayback =>
      'Aplicar un mpv.conf propio antes de empezar la reproducción';

  @override
  String get unsafeAdvancedMpvOptions => 'Opciones avanzadas de mpv no seguras';

  @override
  String get unsafeMpvOptionsDescription =>
      'Permitir más opciones de mpv. Puede afectar al funcionamiento de la reproducción.';

  @override
  String get hardwareDecoding => 'Decodificación por hardware';

  @override
  String get hardwareDecodingSubtitle =>
      'Puede mejorar el rendimiento, pero también dar problemas de reproducción en algunos dispositivos.';

  @override
  String get nextUpAndQueuing => 'A continuación y cola';

  @override
  String get nextUpDisplay => 'Comportamiento de A continuación';

  @override
  String get extended => 'Extendido';

  @override
  String get minimal => 'Mínimo';

  @override
  String get nextUpTimeout => 'Tiempo de espera de A continuación';

  @override
  String secondsValue(int value) {
    return '$value s';
  }

  @override
  String get autoQueueNextEpisodes =>
      'Añadir automáticamente los siguientes episodios a la cola';

  @override
  String get stillWatchingPrompt => 'Aviso de «¿Sigues viendo?»';

  @override
  String afterEpisodesAndHours(int episodes, double hours) {
    return 'Tras $episodes episodios / $hours h';
  }

  @override
  String get resumeAndSkip => 'Reanudar y saltar';

  @override
  String get resumeRewind => 'Retroceso al reanudar';

  @override
  String get unpauseRewind => 'Retroceso al quitar la pausa';

  @override
  String get fiveSeconds => '5 segundos';

  @override
  String get tenSeconds => '10 segundos';

  @override
  String get fifteenSeconds => '15 segundos';

  @override
  String get thirtySeconds => '30 segundos';

  @override
  String get skipBackLength => 'Duración del salto atrás';

  @override
  String get skipForwardLength => 'Duración del salto adelante';

  @override
  String get customMpvConfPath => 'Ruta del mpv.conf personalizado';

  @override
  String get notSetMpvConf =>
      'Sin configurar. kOS TV buscará un mpv.conf predeterminado en las carpetas de la app o de datos.';

  @override
  String get selectMpvConf => 'Seleccionar mpv.conf';

  @override
  String get pathToMpvConf => '/ruta/a/mpv.conf';

  @override
  String get subtitleStyleDescription =>
      'Los ajustes de estilo (tamaño, color, desplazamiento) se aplican a los subtítulos de texto (SRT, VTT, TTML). Los subtítulos ASS/SSA usan su propio estilo incrustado, salvo que se desactive «Reproducción directa de ASS/SSA». A los subtítulos de mapa de bits (PGS, DVB, VobSub) no se les puede cambiar el estilo.';

  @override
  String get defaultSubtitleLanguage => 'Idioma de subtítulos predeterminado';

  @override
  String get subtitleDownloadLanguages => 'Idiomas para descargar subtítulos';

  @override
  String get subtitleDownloadLanguagesDescription =>
      'Idiomas en los que buscar al descargar subtítulos, hasta 5. Automático busca en un idioma elegido a partir de tu idioma de subtítulos predeterminado o del vídeo.';

  @override
  String get preferredSecondarySubtitleLanguage =>
      'Idioma preferido de los subtítulos secundarios';

  @override
  String get secondarySubtitlesEnabledSubtitle =>
      'Muestra una segunda pista de subtítulos a la vez. El menú de subtítulos te preguntará antes si quieres elegir la pista principal o la secundaria';

  @override
  String get defaultToNoSubtitles => 'Sin subtítulos por defecto';

  @override
  String get turnOffSubtitlesByDefault => 'Desactivar subtítulos por defecto';

  @override
  String get subtitleSize => 'Tamaño de subtítulos';

  @override
  String get primarySubtitleSlot => 'Pista principal';

  @override
  String get secondarySubtitleSlot => 'Pista secundaria';

  @override
  String get secondarySubtitleTrack => 'Subtítulos secundarios';

  @override
  String get secondaryDelayAdjustment => 'Ajuste del retardo secundario';

  @override
  String decreaseValue(String setting) {
    return 'Reducir $setting';
  }

  @override
  String increaseValue(String setting) {
    return 'Aumentar $setting';
  }

  @override
  String get textFillColor => 'Color de relleno del texto';

  @override
  String get backgroundColor => 'Color de fondo';

  @override
  String get textStrokeColor => 'Color del trazo del texto';

  @override
  String get subtitleCustomization => 'Personalización de subtítulos';

  @override
  String get subtitleCustomizationDescription =>
      'Personalizar la apariencia de los subtítulos';

  @override
  String get subtitleMode => 'Modo de subtítulos';

  @override
  String get subtitleModeFlagged => 'Marcados';

  @override
  String get subtitleModeAlways => 'Siempre';

  @override
  String get subtitleModeForeign => 'Idioma extranjero';

  @override
  String get subtitleModeForced => 'Forzados';

  @override
  String get subtitleModeFlaggedDescription =>
      'Reproduce las pistas marcadas internamente como \"predeterminadas\" o \"forzadas\" en los metadatos del archivo.';

  @override
  String get subtitleModeAlwaysDescription =>
      'Carga y muestra los subtítulos automáticamente cada vez que empieza un vídeo.';

  @override
  String get subtitleModeForeignDescription =>
      'Activa los subtítulos automáticamente si la pista de audio predeterminada está en un idioma extranjero.';

  @override
  String get subtitleModeForcedDescription =>
      'Solo carga los subtítulos etiquetados explícitamente con la marca de metadatos \"forzado\".';

  @override
  String get subtitleModeNoneDescription =>
      'Desactiva por completo la carga automática de subtítulos.';

  @override
  String get fallbackSubtitleLanguage => 'Idioma de subtítulos alternativo';

  @override
  String get subtitleStream => 'Pista de subtítulos';

  @override
  String get subtitlePreviewText =>
      'El veloz murciélago hindú comía feliz cardillo y kiwi';

  @override
  String get verticalOffset => 'Desplazamiento vertical';

  @override
  String get pgsDirectPlay => 'Reproducción directa de PGS';

  @override
  String get directPlayPgsSubtitles => 'Reproducción directa de subtítulos PGS';

  @override
  String get assSsaDirectPlay => 'Reproducción directa de ASS/SSA';

  @override
  String get directPlayAssSsaSubtitles =>
      'Reproducción directa de subtítulos ASS/SSA';

  @override
  String get white => 'Blanco';

  @override
  String get black => 'Negro';

  @override
  String get yellow => 'Amarillo';

  @override
  String get green => 'Verde';

  @override
  String get cyan => 'Cian';

  @override
  String get red => 'Rojo';

  @override
  String get transparent => 'Transparente';

  @override
  String get semiTransparentBlack => 'Negro semitransparente';

  @override
  String get semiTransparentWhite => 'Blanco semitransparente';

  @override
  String get lightGray => 'Gris claro';

  @override
  String get darkGray => 'Gris oscuro';

  @override
  String get blue => 'Azul';

  @override
  String get magenta => 'Magenta';

  @override
  String get global => 'Global';

  @override
  String get desktop => 'Escritorio';

  @override
  String get mobile => 'Móvil';

  @override
  String get tv => 'TV';

  @override
  String loadedProfileSettings(String profile) {
    return 'Se han cargado los ajustes del perfil $profile.';
  }

  @override
  String failedToLoadProfileSettings(String profile) {
    return 'No se han podido cargar los ajustes del perfil $profile.';
  }

  @override
  String syncedSettingsToProfile(String profile) {
    return 'Ajustes locales sincronizados con el perfil $profile.';
  }

  @override
  String get syncing => 'Sincronizando...';

  @override
  String resetProfileTitle(String profile) {
    return '¿Restablecer $profile?';
  }

  @override
  String resetProfileDescription(String profile) {
    return 'Esto borra el perfil $profile del servidor y devuelve todos los ajustes sincronizados de este dispositivo a su valor predeterminado.';
  }

  @override
  String get resetGlobalProfileDescription =>
      'Esto borra todos los perfiles guardados en el servidor y devuelve todos los ajustes sincronizados de este dispositivo a su valor predeterminado.';

  @override
  String profileReset(String profile) {
    return 'Perfil $profile restablecido a los valores predeterminados.';
  }

  @override
  String get resetRatingsTitle => '¿Restablecer valoraciones?';

  @override
  String get resetRatingsDescription =>
      'Esto devuelve todos los ajustes de valoraciones a su valor predeterminado, incluidas las fuentes que se muestran y el orden en que aparecen.';

  @override
  String get ratingsReset =>
      'Valoraciones restablecidas a los valores predeterminados.';

  @override
  String failedToResetProfile(String profile) {
    return 'No se pudo restablecer el perfil $profile.';
  }

  @override
  String get profileSyncHidden => 'Sincronización de perfil oculta';

  @override
  String get enablePluginSyncDescription =>
      'Activa la sincronización con el complemento del servidor en los ajustes del complemento para ver aquí los controles de perfil.';

  @override
  String get quality => 'Calidad';

  @override
  String get defaultDownloadQuality => 'Calidad de descarga predeterminada';

  @override
  String get network => 'Red';

  @override
  String get wifiOnlyDownloads => 'Descargas solo por WiFi';

  @override
  String get tvOfflineDownloads => 'Activar descargas sin conexión';

  @override
  String get tvOfflineDownloadsSubtitle =>
      'Muestra las opciones de descarga en las páginas de los títulos';

  @override
  String get reportDownloadsActivity => 'Mostrar las descargas en el servidor';

  @override
  String get reportDownloadsActivitySubtitle =>
      'Permite que el administrador del servidor vea tus descargas transcodificadas en el panel de control';

  @override
  String get onlyDownloadOnWifi => 'Solo descargar con conexión WiFi';

  @override
  String get storage => 'Almacenamiento';

  @override
  String get storageUsed => 'Almacenamiento usado';

  @override
  String get manage => 'Gestionar';

  @override
  String get calculating => 'Calculando...';

  @override
  String get downloadLocation => 'Ubicación de descarga';

  @override
  String get defaultLabel => 'Predeterminado';

  @override
  String get sdCard => 'Tarjeta SD';

  @override
  String get downloadLocationLimitedByAndroid =>
      'Android solo deja que kOS TV escriba en sus propias carpetas, y este dispositivo no tiene almacenamiento extraíble. Activa «Guardar en la carpeta de Descargas», arriba, para guardar las descargas donde otras apps puedan acceder a ellas.';

  @override
  String get saveToDownloadsFolder => 'Guardar en la carpeta de Descargas';

  @override
  String get downloadsVisibleToOtherApps =>
      'Descargas/KosTV — visible para otras apps';

  @override
  String get dangerZone => 'Zona peligrosa';

  @override
  String get clearAllDownloads => 'Borrar todas las descargas';

  @override
  String get original => 'Original';

  @override
  String get changeDownloadLocation => 'Cambiar ubicación de descarga';

  @override
  String get changeDownloadLocationDescription =>
      'Las nuevas descargas se guardarán en la carpeta seleccionada. Las descargas existentes permanecerán en su ubicación actual y se pueden gestionar desde los ajustes de Almacenamiento.';

  @override
  String get confirm => 'Confirmar';

  @override
  String get cannotWriteToFolder =>
      'No se puede escribir en la carpeta seleccionada. Elige otra ubicación o concede permisos de almacenamiento.';

  @override
  String get saveToDownloadsFolderQuestion =>
      '¿Guardar en la carpeta de Descargas?';

  @override
  String get saveToDownloadsFolderDescription =>
      'El contenido descargado se guardará en Descargas/KosTV en tu dispositivo. Estos archivos serán visibles para otras apps, como la galería o el reproductor de música.\n\nLas descargas que ya tienes se quedan donde están.';

  @override
  String get transcodingTimeRemainingUnavailable =>
      'Transcodificando: tiempo restante no disponible';

  @override
  String get enable => 'Activar';

  @override
  String get clearAllDownloadsWarning =>
      'Esto eliminará todo el contenido descargado y no se puede deshacer.';

  @override
  String get clearAll => 'Borrar todo';

  @override
  String get navigationStyle => 'Estilo de navegación';

  @override
  String get topBar => 'Barra superior';

  @override
  String get leftSidebar => 'Barra lateral izquierda';

  @override
  String get showShuffleButton => 'Mostrar botón de aleatorio';

  @override
  String get showGenresButton => 'Mostrar botón de géneros';

  @override
  String get showFavoritesButton => 'Mostrar botón de favoritos';

  @override
  String get showLiveTvButton => 'Mostrar botón de TV en directo';

  @override
  String get showDownloadsButton => 'Mostrar botón de Descargas';

  @override
  String get showLibrariesInToolbar =>
      'Mostrar bibliotecas en la barra de herramientas';

  @override
  String get showLibrariesIndividually => 'Mostrar bibliotecas por separado';

  @override
  String get showLibrariesIndividuallySubtitle =>
      'Muestra cada biblioteca como un botón propio en la barra de navegación en lugar de en el menú Bibliotecas';

  @override
  String get navbarAlwaysExpanded =>
      'Expandir siempre las etiquetas de la barra de navegación';

  @override
  String get navbarOpacity => 'Opacidad de la barra de navegación';

  @override
  String get navbarColor => 'Color de la barra de navegación';

  @override
  String get gray => 'Gris';

  @override
  String get darkBlue => 'Azul oscuro';

  @override
  String get purple => 'Púrpura';

  @override
  String get teal => 'Verde azulado';

  @override
  String get navy => 'Azul marino';

  @override
  String get charcoal => 'Gris carbón';

  @override
  String get brown => 'Marrón';

  @override
  String get darkRed => 'Rojo oscuro';

  @override
  String get darkGreen => 'Verde oscuro';

  @override
  String get slate => 'Gris pizarra';

  @override
  String get indigo => 'Índigo';

  @override
  String get kostvColorCyan => 'Cian kOS TV';

  @override
  String get kostvColorNeonMagenta => 'Magenta neón';

  @override
  String get kostvColorEightBitGold => 'Oro 8 bits';

  @override
  String get libraryDisplay => 'Visualización de biblioteca';

  @override
  String get posterLabel => 'Póster';

  @override
  String get thumbnailLabel => 'Miniatura';

  @override
  String get bannerLabel => 'Banner';

  @override
  String get overridePerLibrarySettings => 'Anular ajustes por biblioteca';

  @override
  String get applyImageTypeToAllLibraries =>
      'Aplicar tipo de imagen a todas las bibliotecas';

  @override
  String get mergeRecentRowsByType => 'Unir filas recientes por tipo';

  @override
  String get mergeRecentRowsByTypeDescription =>
      'Combina bibliotecas distintas del mismo tipo en las filas «Añadido recientemente» y «Lanzado recientemente» de Inicio.';

  @override
  String get libraryView => 'Vista de biblioteca';

  @override
  String get libraryStyle => 'Estilo de la biblioteca de vídeo';

  @override
  String get libraryStyleDescription =>
      'Clásico es la cabecera original con botones de iconos. Moderno reúne la búsqueda y botones con texto para ordenar, agrupar y filtrar en una sola barra. Acoplado lleva los controles y las letras a un panel lateral.';

  @override
  String get libraryStyleDescriptionPhone =>
      'Clásico es la cabecera original con botones de iconos. Moderno añade botones con texto para ordenar, agrupar y filtrar bajo la búsqueda. Acoplado deja los controles en una barra en la parte inferior de la pantalla.';

  @override
  String get libraryStyleClassic => 'Clásico';

  @override
  String get libraryStyleModern => 'Moderno';

  @override
  String get libraryStyleDocked => 'Acoplado';

  @override
  String get bookLibraryStyle => 'Estilo de la biblioteca de libros';

  @override
  String get bookLibraryStyleDescription =>
      'Clásico son las estanterías originales bajo un título destacado. Sala de lectura empieza con lo que estás leyendo en tarjetas grandes. Librería recorre toda la biblioteca en una cuadrícula.';

  @override
  String get bookLibraryStyleClassic => 'Clásico';

  @override
  String get bookLibraryStyleReadingRoom => 'Sala de lectura';

  @override
  String get bookLibraryStyleBookstore => 'Librería';

  @override
  String get musicLibraryStyle => 'Estilo de la biblioteca de música';

  @override
  String get musicLibraryStyleDescription =>
      'Clásico son las filas originales bajo una tarjeta Vuelve a escuchar. Acceso rápido empieza con una cuadrícula de tus álbumes y listas de reproducción recientes. Inmersivo empieza con el álbum que estás escuchando.';

  @override
  String get musicLibraryStyleClassic => 'Clásico';

  @override
  String get musicLibraryStyleQuickAccess => 'Acceso rápido';

  @override
  String get musicLibraryStyleImmersive => 'Inmersivo';

  @override
  String get jumpBackIn => 'Vuelve a escuchar';

  @override
  String get yourPlaylists => 'Tus listas de reproducción';

  @override
  String get fromThisAlbum => 'De este álbum';

  @override
  String get searchMusic => 'Buscar música';

  @override
  String bookSeriesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count series',
      one: '1 serie',
    );
    return '$_temp0';
  }

  @override
  String bookInProgressCount(int count) {
    return '$count en curso';
  }

  @override
  String bookBrowseAllTitles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ver los $count títulos',
      one: 'Ver 1 título',
    );
    return '$_temp0';
  }

  @override
  String get searchBooks => 'Buscar libros';

  @override
  String get libraryShowLabel => 'Mostrar';

  @override
  String get libraryAToZ => 'A-Z';

  @override
  String get libraryJumpToLetter => 'Ir a la letra';

  @override
  String get groupItemsIntoCollections => 'Agrupar elementos en colecciones';

  @override
  String get hideCollectionAssociatedItems =>
      'Ocultar los elementos de la biblioteca asociados a una colección al explorar las bibliotecas';

  @override
  String get groupItemsIntoCollectionsDialogTitle =>
      'Aviso sobre la agrupación de bibliotecas';

  @override
  String get groupItemsIntoCollectionsDialogMessage =>
      'Para usar este ajuste, asegúrate de que los ajustes de biblioteca \"Agrupar películas en colecciones\" o \"Agrupar series en colecciones\" estén activados en los ajustes de Visualización de tu biblioteca en tu servidor de Jellyfin.';

  @override
  String get libraryVisibility => 'Visibilidad de la biblioteca';

  @override
  String get libraryVisibilityDescription =>
      'Muestra u oculta cada biblioteca en la página de inicio. Reinicia kOS TV para aplicar los cambios.';

  @override
  String get showInNavigation => 'Mostrar en la navegación';

  @override
  String get showInLatestMedia => 'Mostrar en contenido reciente';

  @override
  String get libraryOrder => 'Orden de las bibliotecas';

  @override
  String get libraryOrderSubtitle => 'Elige el orden de tus bibliotecas';

  @override
  String get libraryOrderDescription =>
      'Tus bibliotecas aparecen en este orden en Mi contenido, en las filas de añadidos recientemente y en la barra de navegación. El orden se guarda en tu cuenta del servidor, así que también lo usan las otras apps en las que inicies sesión.';

  @override
  String get libraryOrderTvHint =>
      'Pulsa izquierda o derecha para mover la biblioteca resaltada.';

  @override
  String get libraryOrderSaveFailed =>
      'No se pudo guardar el orden de las bibliotecas';

  @override
  String get sourceLibraries => 'Bibliotecas de origen';

  @override
  String get sourceCollections => 'Colecciones de origen';

  @override
  String get excludedGenres => 'Géneros excluidos';

  @override
  String get selectAll => 'Seleccionar todo';

  @override
  String itemsSelected(int count) {
    return '$count seleccionados';
  }

  @override
  String get mediaBar => 'Barra multimedia';

  @override
  String get mediaSources => 'Fuentes multimedia';

  @override
  String get behavior => 'Comportamiento';

  @override
  String get seconds => 'segundos';

  @override
  String get mediaBarMode => 'Estilo de la barra multimedia';

  @override
  String get mediaBarModeDescription =>
      'Elige entre varios estilos de barra multimedia o desactiva la barra multimedia';

  @override
  String get peekHomeRows => 'Asomar las filas de Inicio';

  @override
  String get peekHomeRowsDescription =>
      'Muestra la mitad superior de la primera fila en la parte inferior de la barra multimedia';

  @override
  String get mediaBarModeMoonfin => 'kOS TV';

  @override
  String get mediaBarModeMakd => 'MakD';

  @override
  String get mediaBarModeOff => 'Desactivado';

  @override
  String get mediaBarModeBookshelf => 'Estantería';

  @override
  String get mediaBarModeGallery => 'Galería';

  @override
  String get mediaBarModeBanner => 'Banner';

  @override
  String get mediaBarModeAya => 'Aya';

  @override
  String get enableMediaBar => 'Activar barra multimedia';

  @override
  String get showFeaturedContentSlideshow =>
      'Mostrar carrusel de contenido destacado en el inicio';

  @override
  String get contentType => 'Tipo de contenido';

  @override
  String get mediaBarSourceType => 'Origen';

  @override
  String get mediaBarSourceRandom => 'Aleatorio';

  @override
  String get mediaBarSourceNewReleases => 'Nuevas temporadas y episodios';

  @override
  String get mediaBarNewReleaseBanner => 'Aviso de novedades';

  @override
  String get mediaBarNewReleaseBannerDescription =>
      'Marca las series con una temporada nueva o con episodios nuevos emitidos hace poco.';

  @override
  String get mediaBarNewReleaseDays => 'Periodo de novedad';

  @override
  String get mediaBarNewReleaseDaysDescription =>
      'Cuánto tiempo después de emitirse un episodio sigue contando como nuevo.';

  @override
  String get mediaBarNewSeries => 'Serie nueva';

  @override
  String get mediaBarNewSeason => 'Temporada nueva';

  @override
  String get mediaBarNewEpisodes => 'Episodios nuevos';

  @override
  String get moviesAndTvShows => 'Películas y series de TV';

  @override
  String get moviesOnly => 'Solo películas';

  @override
  String get tvShowsOnly => 'Solo series de TV';

  @override
  String get itemCount => 'Cantidad de elementos';

  @override
  String get noneSelected => 'Ninguno seleccionado';

  @override
  String get noneExcluded => 'Ninguno excluido';

  @override
  String get autoAdvance => 'Avance automático';

  @override
  String get autoAdvanceSlides =>
      'Avanzar automáticamente a la siguiente diapositiva';

  @override
  String get autoAdvanceInterval => 'Intervalo de avance automático';

  @override
  String get trailerPreview => 'Vista previa de tráiler';

  @override
  String get autoPlayTrailers =>
      'Reproducir tráilers automáticamente en la barra multimedia después de 3 segundos';

  @override
  String get trailerAudio => 'Audio del tráiler';

  @override
  String get enableTrailerAudio =>
      'Activar el audio de los tráileres en la barra multimedia';

  @override
  String get trailerVolume => 'Volumen de los tráileres';

  @override
  String get trailerVolumeDescription =>
      'Volumen al que suenan los tráileres de la barra multimedia';

  @override
  String get trailerCaptions => 'Subtítulos de los tráileres';

  @override
  String get trailerCaptionsDescription =>
      'Muestra subtítulos en los tráileres de YouTube';

  @override
  String get episodePreview => 'Vista previa de episodio';

  @override
  String get mediaPreview => 'Vista previa de contenido';

  @override
  String get episodePreviewDescription =>
      'Reproducir una vista previa de 30 segundos en la tarjeta seleccionada, al pasar el cursor por encima o al mantenerla pulsada';

  @override
  String get mediaPreviewDescription =>
      'Reproducir una vista previa de 30 segundos en la tarjeta seleccionada, al pasar el cursor por encima o al mantenerla pulsada';

  @override
  String get previewAudio => 'Audio de vista previa';

  @override
  String get enablePreviewAudio => 'Activar el audio de las vistas previas';

  @override
  String get previewVolume => 'Volumen de las vistas previas';

  @override
  String get previewVolumeDescription =>
      'Volumen al que suenan las vistas previas de las tarjetas';

  @override
  String get latestMedia => 'Contenido reciente';

  @override
  String get recentlyReleased => 'Lanzamientos recientes';

  @override
  String get recentlyReleasedSeriesType =>
      'Ordenar las series lanzadas recientemente por';

  @override
  String get recentlyReleasedSeriesTypeDescription =>
      'Ordena las filas de Inicio de series lanzadas recientemente por serie, última temporada o fecha de emisión del último episodio';

  @override
  String get myMedia => 'Mi contenido';

  @override
  String get myMediaSmall => 'Mi contenido (pequeño)';

  @override
  String get continueWatching => 'Continuar viendo';

  @override
  String get resumeAudio => 'Reanudar audio';

  @override
  String get resumeBooks => 'Reanudar libros';

  @override
  String get activeRecordings => 'Grabaciones activas';

  @override
  String get playlists => 'Listas de reproducción';

  @override
  String get liveTV => 'TV en directo';

  @override
  String get favoriteChannels => 'Canales favoritos';

  @override
  String get resetToDefaults => 'Restablecer valores predeterminados';

  @override
  String get homeRowPosterSize => 'Tamaño de póster en filas del inicio';

  @override
  String get configureImageTypeForEachRow =>
      'Configurar el tipo de imagen de cada fila activada del inicio';

  @override
  String get mergeContinueWatchingAndNextUp =>
      'Fusionar Continuar viendo y A continuación';

  @override
  String get combineBothRows =>
      'Combinar ambas filas en una sola sección del inicio';

  @override
  String get continueWatchingDefaultAction => 'Acción predeterminada';

  @override
  String get continueWatchingDefaultActionDescription =>
      'Qué pasa al seleccionar un elemento de Continuar viendo o de A continuación';

  @override
  String get goToDetailsScreen => 'Ir a los detalles';

  @override
  String get playImmediately => 'Reproducir directamente';

  @override
  String get nextUpMaxDays => 'Días máximos en A continuación';

  @override
  String get nextUpMaxDaysDescription =>
      'Cuánto tiempo sigue una serie en A continuación desde la última vez que la viste';

  @override
  String daysValue(int days) {
    return '$days días';
  }

  @override
  String get fullScreenRows => 'Filas del inicio expandidas';

  @override
  String get fullScreenRowsDescription =>
      'Limitar las filas del inicio a 1 por pantalla';

  @override
  String get homeRowsPadding => 'Separación de filas en Inicio';

  @override
  String get homeRowsPaddingDescription =>
      'Personalizar el espaciado entre filas de inicio';

  @override
  String get homeRowsGenresAndStudios => 'Géneros y estudios';

  @override
  String get homeRowsExternalLists => 'Listas externas';

  @override
  String get perRowSettings => 'Ajustes por fila';

  @override
  String get autoLogin => 'Inicio de sesión automático';

  @override
  String get lastUser => 'Último usuario';

  @override
  String get currentUser => 'Usuario actual';

  @override
  String get alwaysAuthenticate => 'Autenticarse siempre';

  @override
  String get requirePasswordWithToken =>
      'Requerir contraseña incluso con token almacenado';

  @override
  String get confirmExit => 'Confirmar salida';

  @override
  String get showConfirmationBeforeExiting =>
      'Mostrar confirmación antes de salir';

  @override
  String get blockContentWithRatings =>
      'Bloquear contenido con las siguientes clasificaciones:';

  @override
  String get noContentRatingsFound =>
      'Aún no se han encontrado clasificaciones de contenido en este servidor.';

  @override
  String get couldNotLoadServerRatings =>
      'No se pudieron cargar las clasificaciones del servidor. Mostrando solo las clasificaciones guardadas.';

  @override
  String get couldNotRefreshRatings =>
      'No se pudieron actualizar las clasificaciones del servidor. Mostrando las clasificaciones guardadas.';

  @override
  String get enablePinCode => 'Activar código PIN';

  @override
  String get pinSynced => 'PIN sincronizado';

  @override
  String get pinResetFailed =>
      'No se pudo borrar el PIN del servidor. Si sigue activo, pide a un administrador del servidor que lo quite.';

  @override
  String get requirePinToAccess => 'Requerir un PIN para acceder a tu cuenta';

  @override
  String get changePin => 'Cambiar PIN';

  @override
  String get setNewPinCode => 'Establecer un nuevo código PIN';

  @override
  String get removePin => 'Eliminar PIN';

  @override
  String get removePinProtection => 'Eliminar protección con código PIN';

  @override
  String get screensaver => 'Salvapantallas';

  @override
  String get inAppScreensaver => 'Salvapantallas de la app';

  @override
  String get enableBuiltInScreensaver => 'Activar el salvapantallas integrado';

  @override
  String get mode => 'Modo';

  @override
  String get libraryArt => 'Imágenes de la biblioteca';

  @override
  String get logo => 'Logotipo';

  @override
  String get clock => 'Reloj';

  @override
  String get timeout => 'Tiempo de espera';

  @override
  String minutesShort(int minutes) {
    return '$minutes min';
  }

  @override
  String get dimmingLevel => 'Nivel de atenuación';

  @override
  String get screensaverDuringAudio => 'Mostrar con música y audiolibros';

  @override
  String get screensaverDuringAudioDescription =>
      'Deja que el salvapantallas se active mientras suena audio, para que la portada no se quede horas en pantalla.';

  @override
  String get sleepAfterIdle => 'Dejar que la tele se suspenda tras';

  @override
  String get sleepAfterIdleDescriptionAndroid =>
      'Cierra kOS TV tras este tiempo sin pulsar ningún botón para que el salvapantallas y el temporizador de apagado de tu tele tomen el relevo. Lo que esté en pausa se detiene antes, así que conserva su punto de reanudación.';

  @override
  String get sleepAfterIdleDescriptionAppleTv =>
      'Tras este tiempo sin pulsar ningún botón, devuelve la pantalla al salvapantallas y al ajuste de reposo de tu Apple TV. kOS TV sigue abierta, así que continúas justo donde lo dejaste.';

  @override
  String get maxAgeRating => 'Clasificación máxima de edad';

  @override
  String get any => 'Cualquiera';

  @override
  String agePlusValue(int age) {
    return '$age+';
  }

  @override
  String get requireAgeRating => 'Requerir clasificación por edad';

  @override
  String get onlyShowRatedContent => 'Mostrar solo contenido clasificado';

  @override
  String get displayClockDuringScreensaver =>
      'Mostrar reloj durante el salvapantallas';

  @override
  String get clockModeStatic => 'Estático';

  @override
  String get clockModeBouncing => 'Rebotando';

  @override
  String get screensaverGeneralSettings => 'Ajustes generales';

  @override
  String get screensaverVisualComponents => 'Componentes visuales';

  @override
  String get screensaverLibraryContent => 'Contenido de la biblioteca';

  @override
  String get screensaverBackdrop => 'Fondo';

  @override
  String get screensaverBackdropBlack => 'Negro';

  @override
  String get screensaverBackdropMoonfin => 'kOS TV';

  @override
  String get screensaverBackdropCalm => 'Calma';

  @override
  String get screensaverBackdropNeonPulse => 'Pulso de neón';

  @override
  String get screensaverBackdropAurora => 'Aurora';

  @override
  String get screensaverAdditionalComponent => 'Componente adicional';

  @override
  String get screensaverComponentMoonfinLogo => 'Logotipo de kOS TV';

  @override
  String get screensaverComponentRunner => 'Runner';

  @override
  String get screensaverComponentMovement => 'Movimiento del componente';

  @override
  String get screensaverComponentPosition => 'Posición del componente';

  @override
  String get screensaverComponentSize => 'Tamaño del componente';

  @override
  String get screensaverSourceLibrariesDefault => 'Todas (predeterminado)';

  @override
  String get rottenTomatoesCritics => 'Rotten Tomatoes (Crítica)';

  @override
  String get rottenTomatoesAudience => 'Rotten Tomatoes (Público)';

  @override
  String get imdb => 'IMDb';

  @override
  String get tmdb => 'TMDB';

  @override
  String get metacritic => 'Metacritic';

  @override
  String get metacriticUser => 'Metacritic (Usuarios)';

  @override
  String get trakt => 'Trakt';

  @override
  String get letterboxd => 'Letterboxd';

  @override
  String get myAnimeList => 'MyAnimeList';

  @override
  String get aniList => 'AniList';

  @override
  String get communityRating => 'Valoración de la comunidad';

  @override
  String get ratings => 'Valoraciones';

  @override
  String get additionalRatings => 'Valoraciones adicionales';

  @override
  String get mdblistWatchingNow => 'Viéndose en MDBList';

  @override
  String get mdblistWatchingNowDescription =>
      'Muestra lo que están viendo ahora los usuarios de MDBList';

  @override
  String watchingNowWatchersCount(int count) {
    return '$count viendo';
  }

  @override
  String watchingNowLiveSummary(String users, String movies, String shows) {
    return '$users viendo ahora · $movies películas · $shows series';
  }

  @override
  String watchingNowLiveSummaryToday(
    String users,
    String movies,
    String shows,
  ) {
    return '$users han visto algo hoy · $movies películas · $shows series';
  }

  @override
  String get showMdbListAndTmdbRatings =>
      'Mostrar valoraciones de MDBList y TMDB';

  @override
  String get ratingLabels => 'Etiquetas de valoración';

  @override
  String get showLabelsNextToIcons =>
      'Mostrar etiquetas junto a los iconos de valoración';

  @override
  String get ratingBadges => 'Insignias de valoración';

  @override
  String get showDecorativeBadges =>
      'Mostrar insignias decorativas detrás de las valoraciones';

  @override
  String get episodeRatings => 'Valoraciones de episodios';

  @override
  String get showRatingsOnEpisodes =>
      'Mostrar valoraciones en episodios individuales';

  @override
  String get ratingSources => 'Fuentes de valoración';

  @override
  String get ratingSourcesDescription =>
      'Activar y reordenar las fuentes de valoración que se muestran en la app';

  @override
  String get pluginDetected => 'Complemento detectado';

  @override
  String get pluginNotDetected => 'Complemento no detectado';

  @override
  String get pluginNotDetectedDescription =>
      'No se detecta el complemento del servidor. Los ajustes locales siguen usando sus valores guardados o los predeterminados.';

  @override
  String get moonbaseAddress => 'Dirección del complemento del servidor';

  @override
  String get pluginConnected => 'Conectado';

  @override
  String pluginConnectedVersion(String version) {
    return 'Conectado, versión $version';
  }

  @override
  String get pluginSyncOn => 'Sincronización activada';

  @override
  String get pluginSyncOff => 'Sincronización desactivada';

  @override
  String get syncProfileDescription =>
      'Este dispositivo se sincroniza con el perfil que elijas hasta que elijas otro.';

  @override
  String get profileAppliesEverywhere => 'Se aplica en todas partes';

  @override
  String get profileOverridesGlobal => 'Prevalece sobre Global';

  @override
  String get profileThisDevice => 'Este dispositivo';

  @override
  String get profileLoad => 'Cargar';

  @override
  String get profileLoadSubtitle => 'Del servidor a este dispositivo';

  @override
  String get profileSaveSubtitle => 'De este dispositivo al servidor';

  @override
  String resetNamedProfile(String profile) {
    return 'Restablecer perfil $profile';
  }

  @override
  String get recentlyAdded => 'Añadido recientemente';

  @override
  String get popularMovies => 'Películas populares';

  @override
  String get upcomingMovies => 'Próximas películas';

  @override
  String get studios => 'Estudios';

  @override
  String get tags => 'Etiquetas';

  @override
  String get enabled => 'Activado';

  @override
  String get hidden => 'Oculto';

  @override
  String get aboutTitle => 'Acerca de';

  @override
  String versionValue(String version) {
    return 'Versión $version';
  }

  @override
  String get openSourceLicenses => 'Licencias de código abierto';

  @override
  String get sourceCode => 'Código fuente';

  @override
  String get checkForUpdatesNow => 'Buscar actualizaciones ahora';

  @override
  String get checksLatestDesktopRelease =>
      'Busca la última versión de escritorio para esta plataforma';

  @override
  String get youAreUpToDate => 'Tienes la última versión.';

  @override
  String get couldNotCheckForUpdates =>
      'No se ha podido comprobar si hay actualizaciones.';

  @override
  String get noCompatibleUpdate =>
      'No se ha encontrado ningún paquete de actualización compatible con esta plataforma.';

  @override
  String get updateChecksNotSupported =>
      'La búsqueda de actualizaciones no es compatible con esta plataforma.';

  @override
  String get updateNotificationsDisabled =>
      'Las notificaciones de actualización están desactivadas.';

  @override
  String get pleaseWaitBeforeChecking => 'Espera antes de volver a comprobar.';

  @override
  String get latestUpdateAlreadyShown =>
      'La última actualización ya se ha mostrado.';

  @override
  String get updateAvailable => 'Actualización disponible.';

  @override
  String updateAvailableVersion(String version) {
    return 'Actualización disponible: v$version';
  }

  @override
  String get updateNotifications => 'Notificaciones de actualización';

  @override
  String get showWhenUpdatesAvailable =>
      'Mostrar cuando haya actualizaciones disponibles';

  @override
  String updateAvailableTitle(String version) {
    return 'v$version disponible';
  }

  @override
  String get readReleaseNotes => 'Leer notas de la versión';

  @override
  String get downloadingUpdate => 'Descargando actualización...';

  @override
  String get updateDownloadFailed =>
      'No se ha podido descargar la actualización. Inténtalo de nuevo.';

  @override
  String get updateNow => 'Actualizar ahora';

  @override
  String get updateInstallPermissionTitle => 'Permitir actualizaciones';

  @override
  String get updateInstallPermissionBody =>
      'Para actualizarse, Kos TV necesita permiso para instalar apps. Se abrirán los ajustes: activa el permiso para Kos TV y vuelve a la app.';

  @override
  String get updateOpenSettings => 'Abrir ajustes';

  @override
  String get updateInstallPermissionMissing =>
      'Kos TV aún no puede instalar apps. Activa el permiso en Ajustes y vuelve a intentarlo.';

  @override
  String get updateInstallFailed =>
      'No se pudo abrir el instalador. Inténtalo de nuevo.';

  @override
  String get kostvServerUnreachable =>
      'No se puede conectar con el servidor. Comprueba la conexión a internet y vuelve a intentarlo.';

  @override
  String get openReleasesPage => 'Abrir página de versiones';

  @override
  String get navigation => 'Navegación';

  @override
  String get watchedIndicatorsBackdrops =>
      'Indicadores de visto, imágenes de fondo';

  @override
  String get focusColorWatchedIndicatorsBackdrops =>
      'Color de enfoque, indicadores de visto, imágenes de fondo';

  @override
  String get navbarStyleToolbarAppearance =>
      'Estilo de la barra de navegación, botones de la barra de herramientas, apariencia';

  @override
  String get featuredContentAppearance => 'Contenido destacado, apariencia';

  @override
  String gbValue(String value) {
    return '$value GB';
  }

  @override
  String mbValue(int value) {
    return '$value MB';
  }

  @override
  String get imageCacheLimit => 'Límite de la caché de imágenes';

  @override
  String get clearImageCache => 'Borrar la caché de imágenes';

  @override
  String get imageCacheCleared => 'Caché de imágenes borrada';

  @override
  String get clear => 'Borrar';

  @override
  String get browse => 'Explorar';

  @override
  String get noResults => 'Sin resultados';

  @override
  String itemsCount(int count) {
    return '$count elementos';
  }

  @override
  String get request => 'Solicitar';

  @override
  String get cancelRequest => 'Cancelar solicitud';

  @override
  String get playInMoonfin => 'Reproducir en kOS TV';

  @override
  String get watchlist => 'Lista de seguimiento';

  @override
  String get approve => 'Aprobar';

  @override
  String get similar => 'Similares';

  @override
  String get recommendations => 'Recomendaciones';

  @override
  String get keep => 'Mantener';

  @override
  String get errorSearchingLibrary => 'Error al buscar en la biblioteca';

  @override
  String budgetAmount(String amount) {
    return 'Presupuesto: \$$amount';
  }

  @override
  String revenueAmount(String amount) {
    return 'Recaudación: \$$amount';
  }

  @override
  String seasonsCount(int count, String label) {
    return '$label: $count';
  }

  @override
  String get server => 'Servidor';

  @override
  String get appearances => 'Apariciones';

  @override
  String get crewSection => 'Equipo técnico';

  @override
  String get downloadingStatus => 'Descargando';

  @override
  String modifiedByName(String name) {
    return 'Modificado por $name';
  }

  @override
  String get completedStatus => 'Completada';

  @override
  String get requestErrorDuplicate => 'Este título ya se ha solicitado';

  @override
  String get requestErrorNoSeasons => 'No quedan temporadas por solicitar';

  @override
  String get requestErrorPermission =>
      'No tienes permiso para hacer esta solicitud';

  @override
  String get allEpisodes => 'Todos los episodios';

  @override
  String get episode => 'Episodio';

  @override
  String get releaseDateLabel => 'Fecha de estreno';

  @override
  String get runtimeLabel => 'Duración';

  @override
  String get originalLanguageLabel => 'Idioma original';

  @override
  String get access => 'Acceso';

  @override
  String get add => 'Añadir';

  @override
  String get address => 'Dirección';

  @override
  String get analytics => 'Analíticas';

  @override
  String get catalog => 'Catálogo';

  @override
  String get content => 'Contenido';

  @override
  String get copy => 'Copiar';

  @override
  String get create => 'Crear';

  @override
  String get disable => 'Desactivar';

  @override
  String get done => 'Hecho';

  @override
  String get edit => 'Editar';

  @override
  String get encoding => 'Codificación';

  @override
  String get error => 'Error';

  @override
  String get forward => 'Avanzar';

  @override
  String get general => 'General';

  @override
  String get go => 'Ir';

  @override
  String get install => 'Instalar';

  @override
  String get installed => 'Instalado';

  @override
  String get interval => 'Intervalo';

  @override
  String get name => 'Nombre';

  @override
  String get networking => 'Redes';

  @override
  String get next => 'Siguiente';

  @override
  String get path => 'Ruta';

  @override
  String get paused => 'En pausa';

  @override
  String get permissions => 'Permisos';

  @override
  String get processing => 'Procesando';

  @override
  String get profile => 'Perfil';

  @override
  String get provider => 'Proveedor';

  @override
  String get refresh => 'Actualizar';

  @override
  String get remote => 'Mando a distancia';

  @override
  String get rename => 'Renombrar';

  @override
  String get revoke => 'Revocar';

  @override
  String get role => 'Rol';

  @override
  String get root => 'Raíz';

  @override
  String get run => 'Ejecutar';

  @override
  String get search => 'Buscar';

  @override
  String get select => 'Seleccionar';

  @override
  String get send => 'Enviar';

  @override
  String get sessions => 'Sesiones';

  @override
  String get set => 'Establecer';

  @override
  String get status => 'Estado';

  @override
  String get stop => 'Detener';

  @override
  String get streaming => 'Transmisión';

  @override
  String get time => 'Hora';

  @override
  String get trickplay => 'Trickplay';

  @override
  String get uninstall => 'Desinstalar';

  @override
  String get up => 'Carpeta superior';

  @override
  String get update => 'Actualizar';

  @override
  String get upload => 'Subir';

  @override
  String get unmute => 'Activar sonido';

  @override
  String get mute => 'Silenciar';

  @override
  String get branding => 'Marca';

  @override
  String get adminDrawerDashboard => 'Panel de control';

  @override
  String get adminDrawerAnalytics => 'Analíticas';

  @override
  String get adminDrawerSettings => 'Ajustes';

  @override
  String get adminDrawerBranding => 'Marca';

  @override
  String get adminDrawerUsers => 'Usuarios';

  @override
  String get adminDrawerLibraries => 'Bibliotecas';

  @override
  String get adminDrawerDisplay => 'Visualización';

  @override
  String get adminDrawerMetadata => 'Metadatos';

  @override
  String get adminDrawerNfo => 'Ajustes de NFO';

  @override
  String get adminDrawerTranscoding => 'Transcodificación';

  @override
  String get adminDrawerResume => 'Reanudar';

  @override
  String get adminDrawerStreaming => 'Transmisión';

  @override
  String get adminDrawerTrickplay => 'Trickplay';

  @override
  String get adminDrawerDevices => 'Dispositivos';

  @override
  String get adminDrawerActivity => 'Actividad';

  @override
  String get adminDrawerNetworking => 'Redes';

  @override
  String get adminDrawerApiKeys => 'Claves API';

  @override
  String get adminDrawerBackups => 'Copias de seguridad';

  @override
  String get adminDrawerLogs => 'Registros';

  @override
  String get adminDrawerScheduledTasks => 'Tareas programadas';

  @override
  String get adminDrawerPlugins => 'Complementos';

  @override
  String get adminDrawerRepositories => 'Repositorios';

  @override
  String get adminDrawerLiveTv => 'TV en directo';

  @override
  String get adminExitTooltip => 'Salir de la administración';

  @override
  String get adminPremiereNoteLiveTv =>
      'La TV en directo necesita Emby Premiere. Sin él, el servidor no importa canales ni graba nada.';

  @override
  String get adminPremiereNoteBackups =>
      'Backup & Restore necesita Emby Premiere cuando termina su periodo de prueba.';

  @override
  String get adminGeneralRunAtStartup =>
      'Ejecutar el servidor al iniciar el sistema';

  @override
  String get adminGeneralLaunchWebApp =>
      'Abrir la app web en el navegador al iniciarse el servidor';

  @override
  String get adminGeneralBannerText =>
      'Texto del aviso de la pantalla de inicio';

  @override
  String get adminGeneralBannerTextHelp =>
      'Se muestra a todos los usuarios en su pantalla de inicio';

  @override
  String get adminGeneralSectionMaintenance => 'Modo de mantenimiento';

  @override
  String get adminGeneralMaintenanceMode =>
      'Poner el servidor en modo de mantenimiento';

  @override
  String get adminGeneralMaintenanceModeHelp =>
      'Los usuarios solo ven el mensaje de mantenimiento.';

  @override
  String get adminGeneralMaintenanceMessage => 'Mensaje de mantenimiento';

  @override
  String get adminGeneralMaintenanceMessageHelp =>
      'Déjalo vacío para mostrar un mensaje genérico en el idioma de cada usuario.';

  @override
  String get adminGeneralSectionUpdates => 'Actualizaciones automáticas';

  @override
  String get adminGeneralAutoUpdate => 'Actualizar el servidor automáticamente';

  @override
  String get adminGeneralAutoRestart =>
      'Reiniciar automáticamente para aplicar las actualizaciones';

  @override
  String get adminGeneralAutoRestartHelp =>
      'El servidor solo se reinicia cuando no hay usuarios activos.';

  @override
  String adminTaskTriggerSystemEvent(String event) {
    return 'Tras un evento del sistema ($event)';
  }

  @override
  String get adminPluginNeedsPremiere =>
      'Necesita Emby Premiere tras una prueba gratuita de 14 días';

  @override
  String get adminEmbyBackupsHelp =>
      'Emby hace las copias de seguridad con su complemento Backup & Restore.';

  @override
  String get adminEmbyBackupsNoPlugin =>
      'El complemento Backup & Restore no está instalado. Instálalo desde el catálogo de complementos para hacer copias de seguridad de este servidor.';

  @override
  String get adminEmbyBackupNow => 'Hacer copia ahora';

  @override
  String get adminEmbyFullBackup => 'Copia completa';

  @override
  String get adminEmbyLightBackups => 'Copias de la base de datos';

  @override
  String adminEmbyBackupServerVersion(String version) {
    return 'Emby $version';
  }

  @override
  String adminEmbyRestoreConfirm(String name) {
    return '¿Restaurar $name? Sustituye las bibliotecas, los ajustes, los usuarios y las contraseñas de este servidor, y el servidor se apaga al terminar. Puede que tengas que volver a iniciarlo tú.';
  }

  @override
  String get adminEmbyRestoreServerId => 'Restaurar el ID del servidor';

  @override
  String get adminEmbyRestoreServerIdHelp =>
      'Desactívalo si restauras la misma copia en más de un servidor.';

  @override
  String get adminEmbyRestoreShuttingDown =>
      'La restauración ha terminado y el servidor se está apagando. Vuelve a iniciarlo si no se reinicia solo.';

  @override
  String get adminHiddenRemotely =>
      'Ocultar en las pantallas de inicio de sesión al conectarse en remoto';

  @override
  String get adminHiddenFromUnusedDevices =>
      'Ocultar en las pantallas de inicio de sesión de los dispositivos en los que nunca ha iniciado sesión';

  @override
  String get adminSimultaneousStreamLimitHelp =>
      'Limita cuántos vídeos puede reproducir este usuario a la vez.';

  @override
  String get adminUnlimited => 'Ilimitado';

  @override
  String get adminAutoRemoteQuality => 'Calidad remota automática (Mbps)';

  @override
  String get adminAutoRemoteQualityHelp =>
      'Se usa en remoto cuando el reproductor está en calidad automática. Déjalo vacío para detectarla.';

  @override
  String get adminAllowCameraUpload => 'Permitir subir fotos de la cámara';

  @override
  String get adminAllowSubtitleDownloading => 'Permitir descargar subtítulos';

  @override
  String get adminAllowMediaConversion => 'Permitir convertir contenido';

  @override
  String get adminAllowSyncTranscoding =>
      'Permitir descargas que necesiten transcodificación';

  @override
  String get adminAllowSharingPersonalItems =>
      'Permitir compartir listas de reproducción con otros usuarios';

  @override
  String get adminAllowPreferenceAccess =>
      'Permitir cambiar su propia contraseña e imagen de perfil';

  @override
  String get adminTagMode => 'Modo de etiquetas';

  @override
  String get adminEmbyConnect => 'Emby Connect';

  @override
  String get adminEmbyConnectUser => 'Usuario o correo de Emby Connect';

  @override
  String get adminEmbyConnectHelp =>
      'Permite a este usuario iniciar sesión desde cualquier app de Emby sin saber la dirección del servidor.';

  @override
  String get adminEmbyConnectLink => 'Vincular';

  @override
  String get adminEmbyConnectUnlink => 'Desvincular';

  @override
  String get adminEmbyConnectLinked => 'Vinculado a Emby Connect';

  @override
  String get adminEmbyConnectPending =>
      'Invitación enviada. La vinculación se hará cuando la acepte.';

  @override
  String get adminEmbyConnectUnlinked =>
      'Vinculación con Emby Connect eliminada';

  @override
  String get adminEmbyConnectNotFound =>
      'No hay ninguna cuenta de Emby Connect con ese usuario o correo.';

  @override
  String get adminLibImportPlaylists =>
      'Importar archivos de listas de reproducción';

  @override
  String get adminLibExcludeFromSearch => 'Excluir de la búsqueda global';

  @override
  String get adminLibForcedSubtitlesOnly =>
      'Descargar solo subtítulos forzados';

  @override
  String get adminLibImportCollections =>
      'Importar colecciones de los descargadores de metadatos';

  @override
  String get adminLibThumbnailInterval =>
      'Intervalo de las miniaturas de vista previa';

  @override
  String adminLibThumbnailEverySeconds(int count) {
    return 'Cada $count segundos';
  }

  @override
  String get adminLibThumbnailAtChapters => 'En las marcas de capítulo';

  @override
  String get adminLibSaveThumbnailsWithMedia =>
      'Guardar las miniaturas de vista previa en las carpetas multimedia';

  @override
  String get adminLibrarySectionMarkers => 'Marcas de intro';

  @override
  String get adminLibIntroDetection => 'Detectar intros';

  @override
  String get adminLibIntroDetectionDuringScan =>
      'Detectar intros al escanear la biblioteca';

  @override
  String get adminProviderEmbyGuide => 'Datos de guía de Emby';

  @override
  String get adminLiveTvEmbyGuideSelectLineup =>
      'Elige una lista de canales. Si no aparece ninguna, revisa el código postal. Las listas de canales necesitan Emby Premiere.';

  @override
  String get adminLiveTvWakeServer =>
      'Despertar el servidor para las grabaciones';

  @override
  String get adminDrawerLiveTvChannels => 'Canales de TV en directo';

  @override
  String get adminPageDescLiveTvChannels =>
      'Activa o desactiva canales y elige su orden';

  @override
  String get adminLiveTvChannelsEmpty =>
      'Aún no hay canales. Aparecerán aquí cuando haya un sintonizador configurado y el servidor haya importado sus canales.';

  @override
  String get adminTranscodingHwaAdvanced => 'Avanzado';

  @override
  String get adminTranscodingHwaHelp =>
      'En Avanzado puedes elegir y ordenar los códecs por hardware.';

  @override
  String get adminTranscodingHwDecoders =>
      'Decodificadores por hardware preferidos';

  @override
  String get adminTranscodingHwEncoders =>
      'Codificadores por hardware preferidos';

  @override
  String get adminTranscodingTempPathHelp =>
      'Donde el transcodificador guarda sus archivos de trabajo. Déjalo vacío para usar la carpeta de datos del servidor.';

  @override
  String get adminTranscodingThrottleHelp =>
      'Ralentiza la transcodificación cuando ya hay suficiente búfer, para usar menos CPU.';

  @override
  String get adminTranscodingDownmixHelp =>
      'Sube el volumen al reducir los canales de audio (downmix). 1 mantiene el volumen original.';

  @override
  String get adminTranscodingFontExtraction =>
      'Permitir extraer fuentes sobre la marcha';

  @override
  String get adminTranscodingMaxResolution =>
      'Resolución máxima de transcodificación';

  @override
  String get adminTranscodingMaxResolutionHelp =>
      'Un límite para todas las transcodificaciones, pida la calidad que pida la app.';

  @override
  String get adminTranscodingToneMapSoftware =>
      'Mapeo de tonos en transcodificaciones por software';

  @override
  String get adminTranscodingToneMapHardware =>
      'Mapeo de tonos en transcodificaciones por hardware';

  @override
  String get adminTranscodingToneMapHelp =>
      'Evita que el vídeo HDR se vea oscuro y desvaído al transcodificarlo.';

  @override
  String get adminNetworkingLocalAddress => 'Dirección IP local';

  @override
  String get adminNetworkingLocalAddressHelp =>
      'La dirección local que el servidor da a las apps. Déjalo vacío para detectarla automáticamente.';

  @override
  String get adminNetworkingBehindProxy =>
      'Un proxy inverso se encarga del HTTPS';

  @override
  String get adminNetworkingExternalDomain => 'Dominio externo';

  @override
  String get adminNetworkingExternalDomainHelp =>
      'Un dominio o nombre de DNS dinámico para las conexiones remotas, sin protocolo ni puerto. Hace falta para usar un certificado personalizado.';

  @override
  String get adminNetworkingUpnp =>
      'Activar la asignación automática de puertos';

  @override
  String get adminNetworkingUpnpHelp =>
      'Intenta asignar el puerto público al puerto local con UPnP. Algunos routers no lo admiten.';

  @override
  String get adminNetworkingProxyHeaders =>
      'Leer las cabeceras del proxy para obtener las direcciones de los clientes';

  @override
  String get adminNetworkingProxyHeadersHelp =>
      'Usa cabeceras como X-Forwarded-For para averiguar la dirección de cada cliente. Actívalo solo si hay un proxy inverso delante.';

  @override
  String get adminNetworkingProxyHeadersRemote =>
      'Solo cuando contengan direcciones remotas';

  @override
  String get adminNetworkingIpv4Only =>
      'Usar IPv4 para las peticiones salientes';

  @override
  String get adminNetworkingIpv4OnlyHelp =>
      'Para cuando no se puede llegar por IPv6 a los proveedores de metadatos y otros servicios.';

  @override
  String get adminOnePerLine => 'Uno por línea';

  @override
  String get adminStreamingStreamLimit =>
      'Máximo de vídeos reproduciéndose a la vez';

  @override
  String get adminStreamingStreamLimitHelp =>
      'Cuántos vídeos se pueden reproducir a la vez en todo el servidor. 0 significa sin límite.';

  @override
  String get adminSyncJobsConversions => 'Trabajos de conversión';

  @override
  String get adminSyncJobsDownloads => 'Trabajos de descarga';

  @override
  String get adminSyncJobsEmpty => 'No hay trabajos';

  @override
  String get adminSyncJobCancel => 'Cancelar trabajo';

  @override
  String adminSyncJobCancelConfirm(String name) {
    return '¿Cancelar $name y quitarlo de la lista?';
  }

  @override
  String get adminSyncJobConverting => 'Convirtiendo';

  @override
  String get adminSyncJobReady => 'Listo para transferir';

  @override
  String get adminSyncJobTransferring => 'Transfiriendo';

  @override
  String get adminSyncJobCompletedWithError => 'Completado con errores';

  @override
  String adminSyncJobItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos',
      one: '1 elemento',
    );
    return '$_temp0';
  }

  @override
  String get adminDrawerDatabase => 'Base de datos';

  @override
  String get adminPageDescDatabase => 'Tamaño de la caché y mantenimiento';

  @override
  String get adminDatabaseWarning =>
      'Son opciones avanzadas. Déjalas con sus valores predeterminados salvo que tengas un motivo para cambiarlas.';

  @override
  String get adminDatabaseCacheSize =>
      'Tamaño de la caché de la base de datos (MB)';

  @override
  String get adminDatabaseCacheSizeHelp =>
      'Cuánto de cada archivo de base de datos guarda el servidor en memoria. Más puede hacer que el servidor vaya más rápido. Se aplica tras reiniciar.';

  @override
  String get adminDatabaseOptimize =>
      'Optimizar la base de datos al apagar el servidor';

  @override
  String get adminDatabaseOptimizeHelp =>
      'Normalmente no hace nada, pero de vez en cuando ejecuta un análisis que ayuda a las consultas del servidor. Los apagados pueden tardar más.';

  @override
  String get adminDatabaseAnalysisLimit => 'Límite de filas del análisis';

  @override
  String get adminDatabaseAnalysisLimitHelp =>
      'Cuántas filas de cada índice lee, aproximadamente, el paso de optimización. Más filas funcionan mejor, pero pueden alargar los apagados.';

  @override
  String get adminDatabaseVacuum =>
      'Compactar (VACUUM) la base de datos en el próximo inicio';

  @override
  String get adminDatabaseVacuumHelp =>
      'Reconstruye el archivo de la base de datos para que ocupe lo mínimo, lo que puede mejorar el rendimiento. Mientras se ejecuta no se puede usar el servidor y no muestra el progreso, así que no lo fuerces a cerrarse. Se vuelve a desactivar solo después de ese inicio.';

  @override
  String get adminDrawerCinemaIntros => 'Intros de cine';

  @override
  String get adminPageDescCinemaIntros =>
      'Tráileres e intros antes de la reproducción';

  @override
  String get adminCinemaIntrosPlayBefore => 'Reproducir intros antes de';

  @override
  String get adminCinemaIntrosUpcoming =>
      'Incluir tráileres de películas nuevas y próximos estrenos';

  @override
  String get adminCinemaIntrosOlder =>
      'Incluir tráileres de películas más antiguas';

  @override
  String get adminCinemaIntrosLibrary =>
      'Incluir tráileres de películas de mis bibliotecas';

  @override
  String get adminCinemaIntrosLibraryHelp =>
      'Necesita tener configurados tráileres locales.';

  @override
  String get adminCinemaIntrosCount => 'Número de tráileres que reproducir';

  @override
  String get adminCinemaIntrosParental => 'Control parental inteligente';

  @override
  String get adminCinemaIntrosParentalHelp =>
      'Solo elige tráileres con la misma clasificación por edades que lo que se está viendo, o inferior.';

  @override
  String get adminCinemaIntrosUnwatchedOnly =>
      'Reproducir intros solo antes de contenido no visto';

  @override
  String get adminCinemaIntrosSimilarOnly =>
      'Reproducir solo tráileres parecidos a lo que se está viendo';

  @override
  String get adminCinemaIntrosSimilarOnlyHelp =>
      'Según los géneros, etiquetas, estudios, etc. que tengan en común.';

  @override
  String get adminCinemaIntrosCustom => 'Intros personalizadas';

  @override
  String get adminCinemaIntrosCustomPath => 'Carpeta de intros personalizadas';

  @override
  String get adminCinemaIntrosCustomPathHelp =>
      'Una carpeta de vídeos. Se elige uno al azar y se reproduce después de los tráileres.';

  @override
  String get adminCinemaIntrosCodecPath => 'Carpeta de intros de códec';

  @override
  String get adminCinemaIntrosCodecPathHelp =>
      'Una carpeta de vídeos. Antes del contenido principal se reproduce uno cuyo nombre de archivo coincida con el códec de vídeo, el códec de audio, el perfil de audio o una etiqueta.';

  @override
  String get adminDrawerDlna => 'DLNA';

  @override
  String get adminPageDescDlna => 'Play To y el servidor DLNA';

  @override
  String get adminDlnaPlayTo => 'Activar DLNA Play To';

  @override
  String get adminDlnaPlayToHelp =>
      'Emby puede encontrar dispositivos en tu red y controlarlos a distancia.';

  @override
  String get adminDlnaServer => 'Activar el servidor DLNA';

  @override
  String get adminDlnaServerHelp =>
      'Permite al servidor transmitir contenido a dispositivos DLNA.';

  @override
  String get adminDlnaDefaultUser => 'Usuario predeterminado';

  @override
  String get adminDlnaDefaultUserHelp =>
      'De quién son las bibliotecas que ven los dispositivos conectados. Un perfil de dispositivo puede cambiarlo.';

  @override
  String get adminDlnaDebugLog => 'Activar el registro de depuración de DLNA';

  @override
  String get adminDlnaDebugLogHelp =>
      'Genera archivos de registro grandes. Actívalo solo para solucionar problemas.';

  @override
  String get adminDrawerCameraUpload => 'Subida desde la cámara';

  @override
  String get adminPageDescCameraUpload =>
      'Dónde se guardan las fotos de los móviles';

  @override
  String get adminCameraUploadPath => 'Carpeta de subida de la cámara';

  @override
  String get adminCameraUploadPathHelp =>
      'Déjalo vacío para usar la carpeta predeterminada. Si usas una carpeta personalizada, también tienes que añadirla como biblioteca.';

  @override
  String get adminCameraUploadSubfolders =>
      'Crear una subcarpeta para cada dispositivo';

  @override
  String get adminDrawerConversions => 'Conversiones';

  @override
  String get adminPageDescConversions => 'Contenido convertido y descargas';

  @override
  String get adminConversionsTempPath => 'Carpeta de archivos temporales';

  @override
  String get adminConversionsTempPathHelp =>
      'Dónde se guarda el contenido mientras se convierte.';

  @override
  String get adminConversionsFullSpeed => 'Convertir a máxima velocidad';

  @override
  String get adminConversionsFullSpeedHelp =>
      'Por defecto, las conversiones van despacio para no cargar el servidor.';

  @override
  String get adminDrawerPremiere => 'Emby Premiere';

  @override
  String get adminPageDescPremiere => 'Estado de la licencia y clave';

  @override
  String get adminPremiereActive => 'Premiere está activo en este servidor.';

  @override
  String get adminPremiereInactive =>
      'Este servidor no tiene clave de Premiere.';

  @override
  String get adminPremiereKeyInvalid =>
      'Hay una clave puesta, pero no está activa. Puede que esté mal escrita o caducada.';

  @override
  String get adminPremiereCurrentKey => 'Clave actual';

  @override
  String get adminPremiereNewKey => 'Clave nueva';

  @override
  String get adminPremiereNewKeyHint =>
      'Pega la clave del correo de Emby Premiere.';

  @override
  String get adminPremiereSaveKey => 'Guardar clave';

  @override
  String get adminPremiereRemoveKey => 'Quitar clave';

  @override
  String get adminPremiereKeyRejected =>
      'Emby guardó la clave, pero no la aceptó.';

  @override
  String get adminPremiereLoadFailed =>
      'No se pudo cargar el estado de Premiere';

  @override
  String get embyPremiereRequiredTitle => 'Hace falta Emby Premiere';

  @override
  String get embyPremiereRequiredBody =>
      'Esto necesita una suscripción activa a Emby Premiere en el servidor.';

  @override
  String get embyPremiereRequiredSaveBody =>
      'Esto necesita una suscripción activa a Emby Premiere. Emby guarda el ajuste, pero no lo usará hasta que Premiere esté activo.';

  @override
  String get embyPremiereLearnMore => 'Más información';

  @override
  String get embyPremiereSaveAnyway => 'Guardar igualmente';

  @override
  String get embyPremiereEnterKey => 'Introducir clave';

  @override
  String get adminPremiereNote =>
      'Necesita Emby Premiere. El servidor guarda este ajuste, pero no lo usará hasta que Premiere esté activo.';

  @override
  String adminExternalIdLabel(String name) {
    return 'ID de $name';
  }

  @override
  String get adminExternalIdTypePerson => 'Persona';

  @override
  String get adminExternalIdTypeArtist => 'Artista';

  @override
  String get adminExternalIdTypeAlbumArtist => 'Artista del álbum';

  @override
  String get adminExternalIdTypeOtherArtist => 'Otro artista';

  @override
  String get adminExternalIdTypeReleaseGroup => 'Grupo de lanzamientos';

  @override
  String get adminExternalIdTypeBook => 'Libro';

  @override
  String get adminPlaybackHwAccelWarning =>
      'La aceleración por hardware puede ser inestable en algunos sistemas. Mantén al día el sistema operativo y los controladores de vídeo, y vuelve a ponerla en «Ninguno» si el vídeo deja de reproducirse.';

  @override
  String get adminLibMetadataChangeHelp =>
      'Los cambios en los ajustes de metadatos se aplican al contenido nuevo. Para actualizar el que ya hay, actualízalo desde su página de detalles o actualiza la biblioteca.';

  @override
  String get adminLibFetcherSettings => 'Ajustes de los buscadores';

  @override
  String adminLibImageOptionsTitle(String type) {
    return 'Opciones de imagen: $type';
  }

  @override
  String get adminLibFetchImages => 'Descargar imágenes';

  @override
  String get adminLibMaxBackdrops => 'Número máximo de fondos por elemento';

  @override
  String get adminLibMinBackdropWidth =>
      'Ancho mínimo de los fondos que se descargan';

  @override
  String get adminImageTypeArt => 'Clearart';

  @override
  String get adminImageTypeBox => 'Caja';

  @override
  String get adminImageTypeBoxRear => 'Caja (trasera)';

  @override
  String get adminImageTypeDisc => 'Disco';

  @override
  String get adminImageTypeMenu => 'Menú';

  @override
  String get adminActivityMediaDetails => 'Detalles del contenido';

  @override
  String get adminNetworkingOtherPublishedUriHint =>
      'p. ej. 192.168.1.0/24=http://192.168.1.5:8096';

  @override
  String get adminMetadataFieldOriginalLanguage => 'Idioma original';

  @override
  String get adminMetadataFieldDateAdded => 'Fecha de adición';

  @override
  String get adminMetadataFieldArtists => 'Artistas';

  @override
  String get adminMetadataFieldAlbumArtists => 'Artistas del álbum';

  @override
  String get adminMetadataFieldAlbum => 'Álbum';

  @override
  String get adminMetadataFieldSeriesName => 'Nombre de la serie';

  @override
  String get adminMetadataFieldEpisodeNumber => 'Número de episodio';

  @override
  String get adminMetadataFieldSeasonNumber => 'Número de temporada';

  @override
  String get adminMetadataFieldTrackNumber => 'Número de pista';

  @override
  String get adminMetadataFieldDiscNumber => 'Número de disco';

  @override
  String get adminMetadataFieldAirTime => 'Hora de emisión';

  @override
  String get adminMetadataFieldRuntime => 'Duración en minutos';

  @override
  String get adminMetadataFieldPlaceOfBirth => 'Lugar de nacimiento';

  @override
  String get adminMetadataFieldBirthDate => 'Fecha de nacimiento';

  @override
  String get adminMetadataFieldBirthYear => 'Año de nacimiento';

  @override
  String get adminMetadataFieldDeathDate => 'Fecha de defunción';

  @override
  String get adminMetadataFieldAspectRatio => 'Relación de aspecto original';

  @override
  String get adminMetadataFieldAirsBeforeSeason =>
      'Se emite antes de la temporada';

  @override
  String get adminMetadataFieldAirsAfterSeason =>
      'Se emite después de la temporada';

  @override
  String get adminMetadataFieldAirsBeforeEpisode =>
      'Se emite antes del episodio';

  @override
  String get adminMetadataNamesHelp =>
      'Separa varios nombres con punto y coma.';

  @override
  String get adminMetadataSectionRatings => 'Valoraciones';

  @override
  String get adminMetadataItemLocked =>
      'Los metadatos de este elemento están bloqueados. Desbloquéalos antes de identificarlo.';

  @override
  String get adminMetadataNameOrIdRequired =>
      'Escribe un nombre o un ID externo.';

  @override
  String get adminLibMetadataReaders => 'Lectores de metadatos';

  @override
  String adminLibSimilarProvidersFor(String type) {
    return 'Proveedores de elementos similares: $type';
  }

  @override
  String get adminLibMediaSegmentProviders =>
      'Proveedores de segmentos multimedia';

  @override
  String get adminLibEnableLibrary => 'Activar la biblioteca';

  @override
  String get adminLibEnableLibraryHelp =>
      'Si desactivas la biblioteca, se oculta en las vistas de todos los usuarios.';

  @override
  String get adminLibSaveLyricsWithMedia =>
      'Guardar las letras en las carpetas multimedia';

  @override
  String get adminLibUseCustomTagDelimiters =>
      'Usar un delimitador de etiquetas personalizado';

  @override
  String get adminLibCustomTagDelimiters =>
      'Delimitador de etiquetas personalizado';

  @override
  String get adminLibCustomTagDelimitersHelp =>
      'Caracteres que se tratan como delimitadores para separar etiquetas.';

  @override
  String get adminLibDelimiterWhitelist => 'Lista blanca de delimitadores';

  @override
  String get adminLibDelimiterWhitelistHelp =>
      'Elementos que no se dividen en etiquetas, uno por línea.';

  @override
  String get adminLibDownloadLanguages => 'Idiomas de descarga';

  @override
  String get adminLibraryFolderRequired =>
      'Añade al menos una carpeta a esta biblioteca.';

  @override
  String get adminRenameLibraryWarning =>
      'Al renombrar una biblioteca se pierden todos sus metadatos. Ten cuidado.';

  @override
  String adminDeleteLibraryConfirm(String name) {
    return '¿Quitar la biblioteca «$name»? Los archivos del disco no se borran.';
  }

  @override
  String get adminDeleteLibraryLocations =>
      'Estas ubicaciones multimedia se quitarán de la biblioteca:';

  @override
  String get adminRefreshMode => 'Modo de actualización';

  @override
  String get adminRefreshModeScan => 'Buscar archivos nuevos y actualizados';

  @override
  String get adminRefreshModeMissing => 'Buscar metadatos que falten';

  @override
  String get adminReplaceTrickplayImages =>
      'Reemplazar las imágenes de trickplay existentes';

  @override
  String get adminRefreshDialogHelp =>
      'Los metadatos se actualizan según los ajustes y los servicios de internet activados en el panel de control.';

  @override
  String adminActivityCount(String shown, String total) {
    return '$shown de $total';
  }

  @override
  String get adminLiveTvTabSources => 'Sintonizadores y guía';

  @override
  String get adminLiveTvTabRecordings => 'Grabaciones';

  @override
  String get adminLiveTvAddTuner => 'Añadir sintonizador';

  @override
  String get adminLiveTvEditTuner => 'Editar sintonizador';

  @override
  String get adminLiveTvTunerType => 'Tipo de sintonizador';

  @override
  String get adminLiveTvDetectDevices => 'Detectar mis dispositivos';

  @override
  String get adminLiveTvNoNewDevices =>
      'No se han encontrado dispositivos nuevos';

  @override
  String get adminLiveTvDrmNote => 'No se importarán los canales con DRM.';

  @override
  String get adminLiveTvTunerSaved => 'Sintonizador guardado';

  @override
  String get adminLiveTvDeleteTuner => 'Eliminar sintonizador';

  @override
  String get adminLiveTvDeleteTunerConfirm =>
      '¿Seguro que quieres eliminar este sintonizador?';

  @override
  String get adminLiveTvDeleteProvider => 'Eliminar proveedor de guía';

  @override
  String get adminLiveTvDeleteProviderConfirm =>
      '¿Seguro que quieres eliminar este proveedor de guía?';

  @override
  String get adminLiveTvProviderSaved => 'Proveedor de guía guardado';

  @override
  String get adminLiveTvAddProvider => 'Añadir proveedor';

  @override
  String get adminLiveTvRefreshGuide => 'Actualizar los datos de la guía';

  @override
  String get adminLiveTvMapChannels => 'Asignar canales';

  @override
  String get adminLiveTvNoTunerChannels =>
      'No se han encontrado canales del sintonizador';

  @override
  String get adminLiveTvXmltvPathHelp =>
      'Una ruta o URL a un archivo XMLTV. El servidor lo lee y comprueba si hay cambios. Crear y actualizar el archivo es cosa tuya.';

  @override
  String adminLiveTvSdCreateAccount(String url) {
    return 'Crea una cuenta en $url';
  }

  @override
  String get adminLiveTvSdSignIn => 'Iniciar sesión';

  @override
  String get adminLiveTvSdLineup => 'Lista de canales';

  @override
  String get adminLiveTvSdSelectLineup =>
      'Elige una lista de canales. Si no aparece ninguna, revisa tu usuario, tu contraseña y tu código postal.';

  @override
  String get adminLiveTvGuideDays => 'Días de datos de guía que descargar';

  @override
  String get adminLiveTvGuideDaysHelp =>
      'Con más días puedes programar grabaciones con más antelación y ver más programación, pero la descarga tarda más. «Automático» elige un valor según el número de canales.';

  @override
  String get adminLiveTvRecordingPath => 'Ruta de grabación predeterminada';

  @override
  String get adminLiveTvRecordingPathHelp =>
      'Dónde se guardan las grabaciones. Si está vacía, se usa la carpeta de datos del programa del servidor.';

  @override
  String get adminLiveTvStartWhenPossible => 'Empezar si es posible';

  @override
  String get adminLiveTvStopWhenPossible => 'Terminar si es posible';

  @override
  String get adminLiveTvMinutesBefore => 'minutos antes';

  @override
  String get adminLiveTvMinutesAfter => 'minutos después';

  @override
  String get adminLiveTvSectionGuide => 'Datos de la guía';

  @override
  String get adminLiveTvSectionDefaultRecording =>
      'Ajustes de grabación predeterminados';

  @override
  String get adminLiveTvSectionMetadata => 'Metadatos de las grabaciones';

  @override
  String adminUserLastActivity(String time) {
    return 'Última actividad: $time';
  }

  @override
  String get adminCurrentPassword => 'Contraseña actual';

  @override
  String get adminChannelAccess => 'Acceso a canales';

  @override
  String get adminDeviceAccess => 'Acceso a dispositivos';

  @override
  String get adminDeleteFromAllLibraries => 'Todas las bibliotecas';

  @override
  String get adminUserDisabledBanner =>
      'Este usuario está desactivado. Quita «Desactivado» en Permisos para que pueda volver a iniciar sesión.';

  @override
  String get adminNewPasswordEmpty =>
      'La contraseña nueva no puede estar vacía';

  @override
  String get adminScheduleStartBeforeEnd =>
      'La hora de inicio tiene que ser anterior a la de fin';

  @override
  String get adminDashboardAlerts => 'Alertas';

  @override
  String get adminSessionGoHome => 'Ir a la pantalla de inicio';

  @override
  String get adminPlayMethodRemux => 'Remux';

  @override
  String get adminPlayMethodDirectStream => 'Transmisión directa';

  @override
  String get adminPlayMethodDirectPlay => 'Reproducción directa';

  @override
  String get adminLogLevelTrace => 'Traza';

  @override
  String get adminLogLevelDebug => 'Depuración';

  @override
  String get adminLogLevelInformation => 'Información';

  @override
  String get adminLogLevelWarning => 'Advertencia';

  @override
  String get adminLogLevelError => 'Error';

  @override
  String get adminLogLevelCritical => 'Crítico';

  @override
  String get adminLogLevelNone => 'Ninguno';

  @override
  String get adminActivityAllUsers => 'Todos los usuarios';

  @override
  String adminTaskLastRan(String time, String duration) {
    return 'Última ejecución: $time; duró $duration.';
  }

  @override
  String get adminTaskResultFailed => 'Fallida';

  @override
  String get adminTaskResultCancelled => 'Cancelada';

  @override
  String get adminTaskResultAborted => 'Interrumpida al apagarse el servidor';

  @override
  String adminDurationSecondsShort(String seconds) {
    return '$seconds s';
  }

  @override
  String get adminDeleteTaskTrigger => 'Eliminar activador de la tarea';

  @override
  String get adminDeleteTaskTriggerConfirm =>
      '¿Seguro que quieres eliminar este activador de la tarea?';

  @override
  String adminTaskTriggerEveryMinutes(String minutes) {
    return 'Cada $minutes minutos';
  }

  @override
  String adminTaskTriggerEveryHours(String hours) {
    return 'Cada $hours horas';
  }

  @override
  String adminTaskMinutesValue(String minutes) {
    return '$minutes minutos';
  }

  @override
  String adminTaskHoursValue(String hours) {
    return '$hours horas';
  }

  @override
  String get adminTimeLimitHours => 'Límite de tiempo (horas)';

  @override
  String get adminTranscodingDecodingFor =>
      'Activar la decodificación por hardware para';

  @override
  String get adminTranscodingThreadCountHelp =>
      'Los hilos máximos que puede usar una transcodificación. Con menos hilos se usa menos CPU, pero puede que no basten para una reproducción fluida.';

  @override
  String get adminTranscodingThreadMax => 'Máximo';

  @override
  String get adminTranscodingFfmpegPath => 'Ruta de FFmpeg';

  @override
  String get adminTranscodingFfmpegPathHelp =>
      'El FFmpeg que ejecuta el servidor. Se configura en el servidor, no aquí.';

  @override
  String get adminTranscodingAudioSeek => 'Estrategia de salto en el audio';

  @override
  String get adminTranscodingAudioSeekHelp =>
      'Cómo gestiona el servidor el audio cuando saltas a otro punto de una emisión HLS.';

  @override
  String get adminTranscodingTrimCopiedAudio => 'Recortar el audio copiado';

  @override
  String get adminTranscodingTranscodeAudio => 'Transcodificar el audio';

  @override
  String get adminResumeMinAudiobookMinutes =>
      'Mínimo para reanudar audiolibros (minutos)';

  @override
  String get adminResumeMinAudiobookHelp =>
      'Los audiolibros que se paran antes de este tiempo cuentan como no reproducidos.';

  @override
  String get adminResumeAudiobookRemaining =>
      'Minutos restantes de audiolibro para reanudar';

  @override
  String get adminResumeAudiobookRemainingHelp =>
      'Los audiolibros que se paran con menos de estos minutos restantes cuentan como reproducidos.';

  @override
  String get adminBrandingSplashSection => 'Pantalla de bienvenida';

  @override
  String get adminBrandingSectionWebClient => 'Cliente web';

  @override
  String get adminBrandingSplashSizeHint =>
      'Las imágenes personalizadas deben tener una relación de aspecto de 16x9 y un tamaño mínimo de 1920x1080.';

  @override
  String get adminNetworkingSectionServerAddress =>
      'Ajustes de la dirección del servidor';

  @override
  String get adminNetworkingSectionHttps => 'Ajustes de HTTPS';

  @override
  String get adminNetworkingSectionRemoteAccess => 'Ajustes de acceso remoto';

  @override
  String get adminNetworkingSectionIpProtocols => 'Protocolos IP';

  @override
  String get adminNetworkingSectionDiscovery => 'Descubrimiento de red';

  @override
  String get adminNetworkingSectionFirewall => 'Ajustes de cortafuegos y proxy';

  @override
  String get adminNetworkingLocalHttpPort => 'Puerto HTTP local';

  @override
  String get adminNetworkingLocalHttpPortHelp =>
      'El número de puerto TCP del servidor HTTP.';

  @override
  String get adminNetworkingEnableHttpsHelp =>
      'Escuchar en el puerto HTTPS. Para que tenga efecto también hace falta un certificado válido.';

  @override
  String get adminNetworkingLocalHttpsPort => 'Puerto HTTPS local';

  @override
  String get adminNetworkingLocalHttpsPortHelp =>
      'El número de puerto TCP del servidor HTTPS.';

  @override
  String get adminNetworkingBaseUrlHelp =>
      'Añade un subdirectorio a la URL del servidor, por ejemplo https://example.com/jellyfin.';

  @override
  String get adminNetworkingBindAddress =>
      'Vincular a una dirección de red local';

  @override
  String get adminNetworkingBindAddressHelp =>
      'Sustituye la dirección IP local del servidor HTTP. Déjalo vacío para vincularlo a todas las direcciones. Si lo cambias, hay que reiniciar.';

  @override
  String get adminNetworkingLanNetworksHelp =>
      'Direcciones IP o entradas IP/máscara de las redes que se tratan como locales para los límites de ancho de banda y de acceso remoto. Déjalo vacío para tratar como locales todas las direcciones RFC1918.';

  @override
  String get adminNetworkingKnownProxiesHelp =>
      'Direcciones IP o nombres de host de los proxies que hay delante de este servidor. Hace falta para leer las cabeceras X-Forwarded-For. Si lo cambias, hay que reiniciar.';

  @override
  String get adminNetworkingCustomCertPath =>
      'Ruta del certificado SSL personalizado';

  @override
  String get adminNetworkingCertPathHelp =>
      'Ruta a un archivo PKCS #12 con un certificado y su clave privada, para usar TLS en un dominio personalizado.';

  @override
  String get adminNetworkingCertPasswordHelp =>
      'Escribe la contraseña si tu certificado la necesita.';

  @override
  String get adminNetworkingAllowRemote =>
      'Permitir conexiones remotas a este servidor';

  @override
  String get adminNetworkingAllowRemoteHelp =>
      'Si está desactivado, se bloquean todas las conexiones remotas.';

  @override
  String get adminNetworkingRemoteIpFilterHelp =>
      'Direcciones IP o entradas IP/máscara de redes remotas. Déjalo vacío para permitir cualquier dirección remota.';

  @override
  String get adminNetworkingRemoteIpFilterMode =>
      'Modo del filtro de direcciones IP remotas';

  @override
  String get adminNetworkingPublicHttpPortHelp =>
      'El puerto público asignado al puerto HTTP local.';

  @override
  String get adminNetworkingPublicHttpsPortHelp =>
      'El puerto público asignado al puerto HTTPS local.';

  @override
  String get adminNetworkingAutoDiscoveryLabel =>
      'Activar la detección automática';

  @override
  String get adminNetworkingAutoDiscoveryHelp =>
      'Permite que las apps encuentren este servidor en el puerto UDP 7359.';

  @override
  String get adminNetworkingSamePublishedUri =>
      'Usar la misma URI publicada del servidor para el acceso interno y el externo';

  @override
  String get adminNetworkingPublishedUri => 'URI publicada del servidor';

  @override
  String get adminNetworkingPublishedUriHelp =>
      'Sustituye la URI que da el servidor, según la interfaz o la dirección IP del cliente.';

  @override
  String get adminNetworkingInternalUri => 'URI interna';

  @override
  String get adminNetworkingInternalUriHelp =>
      'URI publicada del servidor para el acceso interno.';

  @override
  String get adminNetworkingExternalUri => 'URI externa';

  @override
  String get adminNetworkingExternalUriHelp =>
      'URI publicada del servidor para el acceso externo.';

  @override
  String get adminNetworkingOtherPublishedUris => 'Otras URI publicadas';

  @override
  String get adminNetworkingOtherPublishedUrisHelp =>
      'URI para una subred o interfaz concreta, escritas como subred=URI.';

  @override
  String get adminBackupsHelp =>
      'Crea y restaura instantáneas de tu servidor. Pueden incluir la base de datos, los metadatos, los subtítulos y las imágenes de Trickplay.';

  @override
  String get adminBackupDisclaimer =>
      'Según el tamaño de tu biblioteca, la copia de seguridad puede tardar un rato.';

  @override
  String get adminBackupTasksWarningTitle => 'Hay tareas programadas en marcha';

  @override
  String get adminBackupTasksWarning =>
      'Detén estas tareas o espera a que terminen antes de crear una copia de seguridad.';

  @override
  String get adminBackupArchiveNotFound =>
      'El servidor no encuentra este archivo de copia de seguridad.';

  @override
  String get adminRestoreInProgress => 'Restauración en curso';

  @override
  String get adminRestoreWaitingForServer =>
      'Esperando a que vuelva el servidor.';

  @override
  String get adminRestoreSucceeded => 'Restauración completada';

  @override
  String get adminLogWatch => 'Seguir';

  @override
  String get adminLogStopWatching => 'Dejar de seguir';

  @override
  String get adminPluginInstallConfirmTitle =>
      'Confirmar la instalación del complemento';

  @override
  String get adminPluginInstallDisclaimer =>
      'Instalar un complemento de terceros tiene riesgos. Puede contener código inestable o malicioso, y puede cambiar en cualquier momento. Instala solo complementos de autores de confianza y ten claro lo que pueden hacer, como consultar servicios externos, ralentizar los escaneos de la biblioteca o añadir trabajo en segundo plano.';

  @override
  String get adminGroupOverview => 'Resumen';

  @override
  String get adminGroupLibrary => 'Biblioteca';

  @override
  String get adminGroupPlayback => 'Reproducción';

  @override
  String get adminGroupPeople => 'Personas';

  @override
  String get adminGroupSystem => 'Sistema';

  @override
  String get adminAreasLabel => 'Áreas de administración';

  @override
  String get adminPagesLabel => 'Páginas';

  @override
  String get adminPageDescDashboard =>
      'Estado del servidor, sesiones y actividad reciente';

  @override
  String get adminPageDescAnalytics =>
      'Tamaño de las bibliotecas, códecs y formatos';

  @override
  String get adminPageDescActivity => 'Todo lo que ha pasado en el servidor';

  @override
  String get adminPageDescTasks => 'Escaneos, limpiezas y sus activadores';

  @override
  String get adminPageDescLibraries =>
      'Carpetas, escáneres y descargadores de metadatos';

  @override
  String get adminPageDescDisplay => 'Cómo ven los usuarios las bibliotecas';

  @override
  String get adminPageDescMetadata => 'Idioma, país e imágenes predeterminados';

  @override
  String get adminPageDescNfo => 'Lectura y guardado de NFO de Kodi';

  @override
  String get adminPageDescLiveTv =>
      'Sintonizadores, datos de la guía y grabaciones';

  @override
  String get adminPageDescTranscoding =>
      'Aceleración por hardware, codificadores, mapeo de tonos';

  @override
  String get adminPageDescResume => 'Cuándo algo cuenta como empezado o visto';

  @override
  String get adminPageDescStreaming => 'Límite de tasa de bits remota';

  @override
  String get adminPageDescTrickplay => 'Miniaturas al avanzar y retroceder';

  @override
  String get adminPageDescUsers => 'Cuentas, acceso y control parental';

  @override
  String get adminPageDescDevices =>
      'Dispositivos con sesión iniciada y sus nombres';

  @override
  String get adminPageDescApiKeys => 'Claves para apps y scripts';

  @override
  String get adminPageDescSettings =>
      'Nombre del servidor, idioma, rutas, rendimiento';

  @override
  String get adminPageDescBranding =>
      'Mensaje de inicio de sesión, CSS personalizado, pantalla de bienvenida';

  @override
  String get adminPageDescNetworking =>
      'Puertos, HTTPS, red local y acceso remoto';

  @override
  String get adminPageDescPlugins => 'Complementos instalados y el catálogo';

  @override
  String get adminPageDescRepositories => 'De dónde vienen los complementos';

  @override
  String get adminPageDescBackups =>
      'Crea y restaura copias de seguridad del servidor';

  @override
  String get adminPageDescLogs => 'Archivos de registro del servidor';

  @override
  String adminSearchSettingsHint(int count) {
    return 'Buscar en $count ajustes';
  }

  @override
  String get adminSearchNoResults => 'Ningún ajuste coincide';

  @override
  String get adminSearchClear => 'Borrar búsqueda';

  @override
  String get adminUnsavedChanges => 'Cambios sin guardar';

  @override
  String get adminDiscard => 'Descartar';

  @override
  String get adminLeaveTitle => '¿Descartar los cambios sin guardar?';

  @override
  String get adminLeaveMessage =>
      'Los cambios de esta página aún no se han guardado.';

  @override
  String get adminKeepEditing => 'Seguir editando';

  @override
  String get adminDashboardLoadFailed => 'Error al cargar el panel de control';

  @override
  String get adminMediaOverview => 'Resumen del contenido';

  @override
  String get adminMediaTotalsError =>
      'No se han podido cargar los totales de contenido del servidor.';

  @override
  String get adminMediaOverviewSubtitle =>
      'Un resumen rápido de cuánto contenido hay en este servidor.';

  @override
  String adminPluginUpdatesAvailable(int count) {
    return 'Actualizaciones de complementos disponibles: $count';
  }

  @override
  String adminPluginsRequiringRestart(int count) {
    return 'Complementos que requieren reinicio: $count';
  }

  @override
  String adminFailedScheduledTasks(int count) {
    return 'Tareas programadas fallidas: $count';
  }

  @override
  String get analyticsMediaDistribution => 'Distribución del contenido';

  @override
  String get analyticsVideoCodecs => 'Códecs de vídeo';

  @override
  String get analyticsAudioCodecs => 'Códecs de audio';

  @override
  String get analyticsContainers => 'Contenedores';

  @override
  String get analyticsTopGenres => 'Principales géneros';

  @override
  String get analyticsReleaseYears => 'Años de lanzamiento';

  @override
  String get analyticsContentRatings => 'Clasificaciones de contenido';

  @override
  String get analyticsRuntimeBuckets => 'Rangos de duración';

  @override
  String get analyticsFileFormats => 'Formatos de archivo';

  @override
  String get analyticsNoData => 'No hay datos disponibles.';

  @override
  String get adminServerInfo => 'Información del servidor';

  @override
  String get adminRestartPending => 'Reinicio pendiente';

  @override
  String get adminServerPaths => 'Rutas del servidor';

  @override
  String get adminServerActions => 'Acciones del servidor';

  @override
  String get adminRestartServer => 'Reiniciar servidor';

  @override
  String get adminShutdownServer => 'Apagar servidor';

  @override
  String get adminLibraryScanStarted => 'Escaneo de bibliotecas iniciado';

  @override
  String errorGeneric(String error) {
    return 'Error: $error';
  }

  @override
  String get adminServerRebootInProgress => 'Reinicio del servidor en curso';

  @override
  String get adminServerRebootMessage =>
      'El servidor se está reiniciando; vuelve a abrir kOS TV';

  @override
  String get adminActiveSessions => 'Sesiones activas';

  @override
  String get adminSessionsLoadFailed => 'Error al cargar las sesiones';

  @override
  String get adminNoActiveSessions => 'No hay sesiones activas';

  @override
  String get adminRecentActivity => 'Actividad reciente';

  @override
  String get adminNoRecentActivity => 'No hay actividad reciente';

  @override
  String adminCommandFailed(String error) {
    return 'Ha fallado el comando: $error';
  }

  @override
  String get adminSendMessage => 'Enviar mensaje';

  @override
  String get adminMessageTextHint => 'Texto del mensaje';

  @override
  String get adminSetVolume => 'Ajustar volumen';

  @override
  String get sessionPrev => 'Anterior';

  @override
  String get sessionRewind => 'Retroceder';

  @override
  String get sessionForward => 'Avanzar';

  @override
  String get sessionNext => 'Siguiente';

  @override
  String get sessionVolumeDown => 'Vol –';

  @override
  String get sessionVolumeUp => 'Vol +';

  @override
  String get nowPlaying => 'Reproduciendo ahora';

  @override
  String get volume => 'Volumen';

  @override
  String get actions => 'Acciones';

  @override
  String get videoCodec => 'Códec de vídeo';

  @override
  String get audioCodec => 'Códec de audio';

  @override
  String get hwAccel => 'Aceleración HW';

  @override
  String get completion => 'Progreso';

  @override
  String get adminClearDates => 'Borrar fechas';

  @override
  String get adminActivitySeverityAll => 'Todas las gravedades';

  @override
  String get adminActivityDateRange => 'Intervalo de fechas';

  @override
  String adminActivityLoadFailed(String error) {
    return 'No se pudo cargar el registro de actividad: $error';
  }

  @override
  String get adminNoActivityEntries => 'No hay entradas de actividad';

  @override
  String get adminEditDeviceName => 'Editar nombre del dispositivo';

  @override
  String get adminCustomName => 'Nombre personalizado';

  @override
  String get adminDeviceNameUpdated => 'Nombre del dispositivo actualizado';

  @override
  String adminDeviceUpdateFailed(String error) {
    return 'No se pudo actualizar el dispositivo: $error';
  }

  @override
  String get adminDeleteDevice => 'Eliminar dispositivo';

  @override
  String get adminDeviceDeleted => 'Dispositivo eliminado';

  @override
  String adminDeviceDeleteFailed(String error) {
    return 'No se pudo eliminar el dispositivo: $error';
  }

  @override
  String adminRemoveDeviceConfirm(String name) {
    return '¿Eliminar el dispositivo «$name»? El usuario tendrá que volver a iniciar sesión en este dispositivo.';
  }

  @override
  String get adminDeleteAllDevices => 'Eliminar todos los dispositivos';

  @override
  String adminDeleteAllDevicesConfirm(int count) {
    return '¿Eliminar $count dispositivos? Los usuarios afectados tendrán que volver a iniciar sesión. Tu dispositivo actual no se verá afectado.';
  }

  @override
  String get adminDevicesDeletedAll => 'Dispositivos eliminados';

  @override
  String adminDevicesDeletedPartial(int count) {
    return 'Se han eliminado algunos dispositivos; $count no se han podido eliminar.';
  }

  @override
  String get adminDevicesLoadFailed => 'Error al cargar los dispositivos';

  @override
  String get adminSearchDevices => 'Buscar dispositivos';

  @override
  String get adminThisDevice => 'Este dispositivo';

  @override
  String get adminEditName => 'Editar nombre';

  @override
  String get adminLibrariesLoadFailed => 'Error al cargar las bibliotecas';

  @override
  String get adminNoLibraries => 'No hay bibliotecas configuradas';

  @override
  String get adminScanAllLibraries => 'Escanear todas las bibliotecas';

  @override
  String get adminAddLibrary => 'Añadir biblioteca';

  @override
  String adminScanFailed(String error) {
    return 'No se pudo iniciar el escaneo: $error';
  }

  @override
  String get adminRenameLibrary => 'Renombrar biblioteca';

  @override
  String get adminNewName => 'Nuevo nombre';

  @override
  String adminLibraryRenamed(String name) {
    return 'Se ha cambiado el nombre de la biblioteca a «$name»';
  }

  @override
  String adminRenameFailed(String error) {
    return 'No se pudo cambiar el nombre: $error';
  }

  @override
  String get adminDeleteLibrary => 'Eliminar biblioteca';

  @override
  String adminLibraryDeleted(String name) {
    return 'Biblioteca \"$name\" eliminada';
  }

  @override
  String adminLibraryDeleteFailed(String error) {
    return 'No se pudo eliminar la biblioteca: $error';
  }

  @override
  String adminAddPathFailed(String error) {
    return 'No se pudo añadir la ruta: $error';
  }

  @override
  String get adminRemovePath => 'Eliminar ruta';

  @override
  String adminRemovePathConfirm(String path) {
    return '¿Eliminar \"$path\" de esta biblioteca?';
  }

  @override
  String adminRemovePathFailed(String error) {
    return 'No se pudo eliminar la ruta: $error';
  }

  @override
  String get adminLibraryLoadFailed => 'Error al cargar la biblioteca';

  @override
  String get adminNoMediaPaths => 'No hay rutas de contenido configuradas';

  @override
  String get adminAddPath => 'Añadir ruta';

  @override
  String get adminBrowseFilesystem =>
      'Explorar el sistema de archivos del servidor:';

  @override
  String get adminPreferredMetadataLanguage => 'Idioma de metadatos preferido';

  @override
  String get adminMetadataLanguageHint => 'p. ej. en, de, fr';

  @override
  String get adminMetadataCountryCode => 'Código de país de metadatos';

  @override
  String get adminMetadataCountryHint => 'p. ej. US, DE, FR';

  @override
  String get adminLibraryTabPaths => 'Rutas';

  @override
  String get adminLibraryTabOptions => 'Opciones';

  @override
  String get adminLibraryTabDownloaders => 'Descargadores';

  @override
  String get adminLibMetadataSavers => 'Guardadores de metadatos';

  @override
  String get adminLibSubtitleDownloaders => 'Descargadores de subtítulos';

  @override
  String get adminLibLyricDownloaders => 'Descargadores de letras';

  @override
  String adminLibMetadataDownloadersFor(String type) {
    return 'Descargadores de metadatos: $type';
  }

  @override
  String adminLibImageFetchersFor(String type) {
    return 'Buscadores de imágenes: $type';
  }

  @override
  String get adminLibNoDownloaders =>
      'Este servidor no ofrece descargadores para este tipo de biblioteca.';

  @override
  String get adminLibrarySectionGeneral => 'General';

  @override
  String get adminLibrarySectionMetadata => 'Metadatos';

  @override
  String get adminLibrarySectionEmbedded => 'Información incrustada';

  @override
  String get adminLibrarySectionSubtitles => 'Subtítulos';

  @override
  String get adminLibrarySectionImages => 'Imágenes';

  @override
  String get adminLibrarySectionSeries => 'Series';

  @override
  String get adminLibrarySectionMusic => 'Música';

  @override
  String get adminLibrarySectionMovies => 'Películas';

  @override
  String get adminLibRealtimeMonitor =>
      'Activar la monitorización en tiempo real';

  @override
  String get adminLibRealtimeMonitorHint =>
      'Detectar los cambios en los archivos y procesarlos automáticamente.';

  @override
  String get adminLibEnablePhotos => 'Mostrar fotos';

  @override
  String get adminLibSaveLocalMetadata =>
      'Guardar las carátulas en las carpetas multimedia';

  @override
  String get adminLibRefreshInterval => 'Actualización automática de metadatos';

  @override
  String get adminLibRefreshNever => 'Nunca';

  @override
  String get adminLibDefault => 'Predeterminado';

  @override
  String get adminLibDisplayTitle => 'Visualización';

  @override
  String get adminLibDisplaySection => 'Visualización de la biblioteca';

  @override
  String get adminLibFolderView =>
      'Mostrar una vista de carpetas para ver las carpetas multimedia normales';

  @override
  String get adminLibSpecialsInSeasons =>
      'Mostrar los especiales dentro de las temporadas en las que se emitieron';

  @override
  String get adminLibGroupMovies => 'Agrupar películas en colecciones';

  @override
  String get adminLibGroupShows => 'Agrupar series en colecciones';

  @override
  String get adminLibExternalSuggestions =>
      'Mostrar contenido externo en las sugerencias';

  @override
  String get adminLibDateAddedSection =>
      'Comportamiento de la fecha de incorporación';

  @override
  String get adminLibDateAddedLabel => 'Usar la fecha de incorporación de';

  @override
  String get adminLibDateAddedImport => 'Fecha de escaneo en la biblioteca';

  @override
  String get adminLibDateAddedFile => 'Fecha de creación del archivo';

  @override
  String get adminLibMetadataTitle => 'Metadatos e imágenes';

  @override
  String get adminLibMetadataLangSection => 'Idioma de metadatos preferido';

  @override
  String get adminLibChaptersSection => 'Capítulos';

  @override
  String get adminLibDummyChapterDuration =>
      'Duración de los capítulos ficticios (segundos)';

  @override
  String get adminLibDummyChapterDurationHint =>
      'Duración de los capítulos generados para el contenido que no tiene ninguno. Establece 0 para desactivarlo.';

  @override
  String get adminLibChapterImageResolution =>
      'Resolución de las imágenes de capítulo';

  @override
  String get adminLibNfoTitle => 'Ajustes de NFO';

  @override
  String get adminLibNfoHelp =>
      'Los metadatos NFO son compatibles con Kodi y clientes similares. Los ajustes se aplican a todas las bibliotecas que guardan metadatos NFO.';

  @override
  String get adminLibKodiUser =>
      'Usuario cuyos datos de visualización se guardarán en los archivos NFO';

  @override
  String get adminLibSaveImagePaths =>
      'Guardar las rutas de las imágenes en los archivos NFO';

  @override
  String get adminLibPathSubstitution =>
      'Activar la sustitución de rutas para las rutas de imagen de los NFO';

  @override
  String get adminLibExtraThumbs =>
      'Copiar las imágenes de extrafanart en una carpeta extrathumbs';

  @override
  String get adminLibNone => 'Ninguno';

  @override
  String adminLibRefreshDays(int days) {
    return '$days días';
  }

  @override
  String get adminLibEmbeddedTitles => 'Usar los títulos incrustados';

  @override
  String get adminLibEmbeddedExtrasTitles =>
      'Usar los títulos incrustados para los extras';

  @override
  String get adminLibEmbeddedEpisodeInfos =>
      'Usar la información de episodio incrustada';

  @override
  String get adminLibAllowEmbeddedSubtitles =>
      'Permitir subtítulos incrustados';

  @override
  String get adminLibEmbeddedAllowAll => 'Permitir todos';

  @override
  String get adminLibEmbeddedAllowText => 'Solo texto';

  @override
  String get adminLibEmbeddedAllowImage => 'Solo imagen';

  @override
  String get adminLibEmbeddedAllowNone => 'Ninguno';

  @override
  String get adminLibSkipIfEmbeddedSubs =>
      'Omitir la descarga si hay subtítulos incrustados';

  @override
  String get adminLibSkipIfAudioMatches =>
      'Omitir la descarga si la pista de audio coincide con el idioma de descarga';

  @override
  String get adminLibRequirePerfectMatch =>
      'Exigir una coincidencia exacta de los subtítulos';

  @override
  String get adminLibSaveSubtitlesWithMedia =>
      'Guardar los subtítulos en las carpetas multimedia';

  @override
  String get adminLibChapterImageExtraction =>
      'Extraer las imágenes de capítulo';

  @override
  String get adminLibChapterImagesDuringScan =>
      'Extraer las imágenes de capítulo durante el escaneo de la biblioteca';

  @override
  String get adminLibTrickplayExtraction =>
      'Activar la extracción de imágenes de trickplay';

  @override
  String get adminLibTrickplayDuringScan =>
      'Extraer las imágenes de trickplay durante el escaneo de la biblioteca';

  @override
  String get adminLibSaveTrickplayWithMedia =>
      'Guardar las imágenes de trickplay en las carpetas multimedia';

  @override
  String get adminLibAutomaticSeriesGrouping =>
      'Fusionar automáticamente las series repartidas en varias carpetas';

  @override
  String get adminLibSeasonZeroName => 'Nombre de la temporada cero';

  @override
  String get adminLibLufsScan =>
      'Activar el análisis LUFS para la normalización del audio';

  @override
  String get adminLibPreferNonstandardArtist =>
      'Preferir la etiqueta de artistas no estándar';

  @override
  String get adminLibAutoAddToCollection =>
      'Añadir películas a las colecciones automáticamente';

  @override
  String get adminLibraryNameRequired =>
      'El nombre de la biblioteca es obligatorio';

  @override
  String adminLibraryCreateFailed(String error) {
    return 'No se pudo crear la biblioteca: $error';
  }

  @override
  String get adminLibraryName => 'Nombre de la biblioteca';

  @override
  String get adminSelectedPaths => 'Rutas seleccionadas:';

  @override
  String get adminCreateLibrary => 'Crear biblioteca';

  @override
  String get paths => 'Rutas:';

  @override
  String get adminDisableUser => 'Desactivar usuario';

  @override
  String get adminEnableUser => 'Activar usuario';

  @override
  String adminDisableUserConfirm(String name) {
    return '¿Desactivar a $name? No podrá iniciar sesión.';
  }

  @override
  String adminEnableUserConfirm(String name) {
    return '¿Activar a $name? Podrá volver a iniciar sesión.';
  }

  @override
  String adminUserDisabled(String name) {
    return 'Usuario \"$name\" desactivado';
  }

  @override
  String adminUserEnabled(String name) {
    return 'Usuario \"$name\" activado';
  }

  @override
  String adminUserPolicyUpdateFailed(String error) {
    return 'No se pudo actualizar la política de usuario: $error';
  }

  @override
  String get adminUsersLoadFailed => 'Error al cargar los usuarios';

  @override
  String get adminSearchUsers => 'Buscar usuarios';

  @override
  String get adminEditUser => 'Editar usuario';

  @override
  String get adminAddUser => 'Añadir usuario';

  @override
  String adminUserCreateFailed(String error) {
    return 'No se pudo crear el usuario: $error';
  }

  @override
  String get adminCreateUser => 'Crear usuario';

  @override
  String get adminPasswordOptional => 'Contraseña (opcional)';

  @override
  String get adminUsernameRequired =>
      'El nombre de usuario no puede estar vacío';

  @override
  String adminSaveFailed(String error) {
    return 'No se pudo guardar: $error';
  }

  @override
  String get adminPasswordsMismatch => 'Las contraseñas no coinciden';

  @override
  String adminFailed(String error) {
    return 'Error: $error';
  }

  @override
  String get adminUserLoadFailed => 'Error al cargar el usuario';

  @override
  String get adminDeleteUser => 'Eliminar usuario';

  @override
  String get admin => 'Administración';

  @override
  String get adminFullAccessWarning =>
      'Los administradores tienen acceso completo al servidor. Concede este permiso con precaución.';

  @override
  String get administrator => 'Administrador';

  @override
  String get adminHiddenUser => 'Usuario oculto';

  @override
  String get adminAllowMediaPlayback => 'Permitir la reproducción de contenido';

  @override
  String get adminAllowAudioTranscoding =>
      'Permitir transcodificación de audio';

  @override
  String get adminAllowVideoTranscoding =>
      'Permitir transcodificación de vídeo';

  @override
  String get adminAllowRemuxing => 'Permitir remuxing';

  @override
  String get adminForceRemoteTranscoding =>
      'Forzar transcodificación de fuente remota';

  @override
  String get adminAllowContentDownloading => 'Permitir descarga de contenido';

  @override
  String get adminAllowPublicSharing => 'Permitir compartir públicamente';

  @override
  String get adminAllowRemoteControl =>
      'Permitir control remoto de otros usuarios';

  @override
  String get adminAllowSharedDeviceControl =>
      'Permitir control de dispositivo compartido';

  @override
  String get adminAllowRemoteAccess => 'Permitir acceso remoto';

  @override
  String get adminLeaveEmptyNoLimit => 'Déjalo vacío para no poner límite';

  @override
  String get adminMaxActiveSessions => 'Máximo de sesiones activas';

  @override
  String get adminAllowLiveTvAccess => 'Permitir acceso a TV en directo';

  @override
  String get adminAllowLiveTvManagement => 'Permitir gestión de TV en directo';

  @override
  String get adminAllowCollectionManagement =>
      'Permitir gestión de colecciones';

  @override
  String get adminAllowSubtitleManagement => 'Permitir gestión de subtítulos';

  @override
  String get adminAllowLyricManagement => 'Permitir gestión de letras';

  @override
  String get adminEnableAllLibraryAccess =>
      'Activar el acceso a todas las bibliotecas';

  @override
  String get adminChangePassword => 'Cambiar contraseña';

  @override
  String get adminNewPassword => 'Nueva contraseña';

  @override
  String get adminConfirmPassword => 'Confirmar contraseña';

  @override
  String get adminSetPassword => 'Establecer contraseña';

  @override
  String get adminResetPassword => 'Restablecer contraseña';

  @override
  String get adminPasswordReset => 'Contraseña restablecida';

  @override
  String get adminPasswordUpdated => 'Contraseña actualizada';

  @override
  String get adminUserSettings => 'Ajustes de usuario';

  @override
  String get adminLibraryAccess => 'Acceso a la biblioteca';

  @override
  String get adminEnableAllDevices =>
      'Activar el acceso a todos los dispositivos';

  @override
  String get adminEnableAllChannels => 'Activar el acceso a todos los canales';

  @override
  String get adminParentalControl => 'Control parental';

  @override
  String get adminMaxParentalRating =>
      'Clasificación parental máxima permitida';

  @override
  String get adminMaxParentalRatingHint =>
      'El contenido con una clasificación superior se ocultará a este usuario.';

  @override
  String get adminParentalRatingNone => 'Ninguna';

  @override
  String get adminBlockUnratedItems =>
      'Bloquear los elementos sin clasificación o con una clasificación no reconocida';

  @override
  String get adminUnratedBook => 'Libros';

  @override
  String get adminUnratedChannelContent => 'Canales';

  @override
  String get adminUnratedLiveTvChannel => 'TV en directo';

  @override
  String get adminUnratedMovie => 'Películas';

  @override
  String get adminUnratedMusic => 'Música';

  @override
  String get adminUnratedTrailer => 'Tráileres';

  @override
  String get adminUnratedSeries => 'Series';

  @override
  String get adminAccessSchedules => 'Horarios de acceso';

  @override
  String get adminAccessSchedulesHint =>
      'Permitir el acceso solo durante los horarios indicados abajo. Si no se define ningún horario, el acceso está permitido todo el día.';

  @override
  String get adminAddSchedule => 'Añadir horario';

  @override
  String get adminScheduleDay => 'Día';

  @override
  String get adminScheduleStart => 'Inicio';

  @override
  String get adminScheduleEnd => 'Fin';

  @override
  String get adminDayEveryday => 'Todos los días';

  @override
  String get adminDayWeekday => 'Días laborables';

  @override
  String get adminDayWeekend => 'Fin de semana';

  @override
  String get adminDaySunday => 'Domingo';

  @override
  String get adminDayMonday => 'Lunes';

  @override
  String get adminDayTuesday => 'Martes';

  @override
  String get adminDayWednesday => 'Miércoles';

  @override
  String get adminDayThursday => 'Jueves';

  @override
  String get adminDayFriday => 'Viernes';

  @override
  String get adminDaySaturday => 'Sábado';

  @override
  String get adminAllowedTags => 'Etiquetas permitidas';

  @override
  String get adminAllowedTagsHint =>
      'Solo se muestra el contenido con estas etiquetas. Déjalo vacío para permitir todo.';

  @override
  String get adminBlockedTags => 'Etiquetas bloqueadas';

  @override
  String get adminBlockedTagsHint =>
      'El contenido con estas etiquetas se oculta a este usuario.';

  @override
  String get adminAddTag => 'Añadir etiqueta';

  @override
  String get adminAuthProvider => 'Proveedor de autenticación';

  @override
  String get adminPasswordResetProvider =>
      'Proveedor de restablecimiento de contraseña';

  @override
  String get adminLoginAttemptsBeforeLockout =>
      'Número máximo de intentos de inicio de sesión fallidos antes del bloqueo';

  @override
  String get adminLoginAttemptsHint =>
      'Establece 0 para el valor predeterminado o -1 para desactivar el bloqueo.';

  @override
  String get adminSyncPlayAccess => 'Acceso a SyncPlay';

  @override
  String get adminSyncPlayCreateAndJoin =>
      'Permitir crear grupos y unirse a ellos';

  @override
  String get adminSyncPlayJoin => 'Permitir unirse a grupos';

  @override
  String get adminSyncPlayNone => 'Sin acceso';

  @override
  String get adminContentDeletionFolders => 'Permitir eliminar contenido de';

  @override
  String get adminResetPasswordWarning =>
      'Esto eliminará la contraseña. El usuario podrá iniciar sesión sin contraseña.';

  @override
  String adminServerReturnedHttp(int status) {
    return 'El servidor devolvió HTTP $status';
  }

  @override
  String adminDeleteUserConfirm(String name) {
    return '¿Seguro que quieres eliminar a $name?';
  }

  @override
  String adminUserDeleted(String name) {
    return 'Usuario \"$name\" eliminado';
  }

  @override
  String adminUserDeleteFailed(String error) {
    return 'No se pudo eliminar el usuario: $error';
  }

  @override
  String get adminCreateApiKey => 'Crear clave API';

  @override
  String get adminAppName => 'Nombre de la app';

  @override
  String get adminApiKeyCreated => 'Clave API creada';

  @override
  String get adminApiKeyCreatedNoToken =>
      'Clave creada correctamente. El servidor no devolvió el token. Comprueba las claves API del servidor.';

  @override
  String get adminKeyCopied => 'Clave copiada al portapapeles';

  @override
  String adminApiKeyCreateFailed(String error) {
    return 'No se pudo crear la clave: $error';
  }

  @override
  String get adminKeyTokenMissing =>
      'Token de clave ausente en la respuesta del servidor';

  @override
  String get adminRevokeApiKey => 'Revocar clave API';

  @override
  String adminRevokeKeyConfirm(String name) {
    return '¿Revocar la clave de $name?';
  }

  @override
  String get adminApiKeyRevoked => 'Clave API revocada';

  @override
  String adminApiKeyRevokeFailed(String error) {
    return 'No se pudo revocar la clave: $error';
  }

  @override
  String get adminApiKeysLoadFailed => 'Error al cargar las claves API';

  @override
  String get adminApiKeysTitle => 'Claves API';

  @override
  String get adminCreateKey => 'Crear clave';

  @override
  String get adminNoApiKeys => 'No se encontraron claves API';

  @override
  String get adminUnknownApp => 'Aplicación desconocida';

  @override
  String adminApiKeyTokenCreated(String token, String created) {
    return 'Token: $token\\nCreado: $created';
  }

  @override
  String get adminBackupOptionsTitle => 'Crear copia de seguridad';

  @override
  String get adminBackupDatabase => 'Base de datos';

  @override
  String get adminBackupDatabaseAlways => 'Siempre incluida';

  @override
  String get adminBackupMetadata => 'Metadatos';

  @override
  String get adminBackupSubtitles => 'Subtítulos';

  @override
  String get adminBackupTrickplay => 'Imágenes de trickplay';

  @override
  String get adminCreatingBackup => 'Creando copia de seguridad...';

  @override
  String get adminBackupCreated => 'Copia de seguridad creada correctamente';

  @override
  String adminBackupCreateFailed(String error) {
    return 'No se pudo crear la copia de seguridad: $error';
  }

  @override
  String get adminBackupPathMissing =>
      'Ruta de copia de seguridad ausente en la respuesta del servidor';

  @override
  String adminBackupManifest(String name) {
    return 'Manifiesto: $name';
  }

  @override
  String adminManifestLoadFailed(String error) {
    return 'No se pudo cargar el manifiesto: $error';
  }

  @override
  String get adminConfirmRestore => 'Confirmar restauración';

  @override
  String get adminRestoringBackup => 'Restaurando copia de seguridad...';

  @override
  String adminRestoreFailed(String error) {
    return 'No se pudo restaurar la copia de seguridad: $error';
  }

  @override
  String get adminBackupsLoadFailed =>
      'Error al cargar las copias de seguridad';

  @override
  String get adminCreateBackup => 'Crear copia de seguridad';

  @override
  String get adminNoBackups => 'No se encontraron copias de seguridad';

  @override
  String get adminViewDetails => 'Ver detalles';

  @override
  String get restore => 'Restaurar';

  @override
  String get adminLogsLoadFailed =>
      'Error al cargar los registros del servidor';

  @override
  String get adminNoLogFiles => 'No se encontraron archivos de registro';

  @override
  String get adminLogCopied => 'Registro copiado al portapapeles';

  @override
  String get adminSaveLogFile => 'Guardar archivo de registro';

  @override
  String adminSavedTo(String path) {
    return 'Guardado en $path';
  }

  @override
  String adminFileSaveFailed(String error) {
    return 'No se pudo guardar el archivo: $error';
  }

  @override
  String adminLogFileLoadFailed(String fileName) {
    return 'No se pudo cargar $fileName';
  }

  @override
  String get adminSearchInLog => 'Buscar en el registro';

  @override
  String get adminNoMatchingLines => 'No hay líneas coincidentes';

  @override
  String adminTasksLoadFailed(String error) {
    return 'No se pudieron cargar las tareas: $error';
  }

  @override
  String get adminNoScheduledTasks => 'No se encontraron tareas programadas';

  @override
  String get adminNoTasksMatchFilter =>
      'Ninguna tarea coincide con el filtro actual';

  @override
  String adminTaskStartFailed(String error) {
    return 'No se pudo iniciar la tarea: $error';
  }

  @override
  String adminTaskStopFailed(String error) {
    return 'No se pudo detener la tarea: $error';
  }

  @override
  String adminTaskLoadFailed(String error) {
    return 'No se pudo cargar la tarea: $error';
  }

  @override
  String get adminRunNow => 'Ejecutar ahora';

  @override
  String adminTriggerRemoveFailed(String error) {
    return 'No se pudo eliminar el disparador: $error';
  }

  @override
  String adminTriggerAddFailed(String error) {
    return 'No se pudo añadir el disparador: $error';
  }

  @override
  String get adminLastExecution => 'Última ejecución';

  @override
  String get adminTriggers => 'Disparadores';

  @override
  String get adminAddTrigger => 'Añadir disparador';

  @override
  String get adminNoTriggers => 'No hay disparadores configurados';

  @override
  String get adminTriggerType => 'Tipo de disparador';

  @override
  String get adminNoLimit => 'Sin límite';

  @override
  String adminHours(String hours) {
    return '$hours hora(s)';
  }

  @override
  String get adminDayOfWeek => 'Día de la semana';

  @override
  String get adminSearchPlugins => 'Buscar complementos...';

  @override
  String adminPluginToggleFailed(String error) {
    return 'No se pudo activar o desactivar el complemento: $error';
  }

  @override
  String get adminUninstallPlugin => 'Desinstalar complemento';

  @override
  String adminUninstallPluginConfirm(String name) {
    return '¿Seguro que quieres desinstalar «$name»?';
  }

  @override
  String adminPluginUninstallFailed(String error) {
    return 'No se pudo desinstalar el complemento: $error';
  }

  @override
  String adminPackageInstallFailed(String error) {
    return 'No se pudo instalar el paquete: $error';
  }

  @override
  String adminPluginUpdateFailed(String error) {
    return 'No se pudo instalar la actualización: $error';
  }

  @override
  String adminPluginsLoadFailed(String error) {
    return 'No se pudieron cargar los complementos: $error';
  }

  @override
  String get adminNoPluginsMatchSearch =>
      'Ningún complemento coincide con tu búsqueda';

  @override
  String get adminNoPluginsInstalled => 'No hay complementos instalados';

  @override
  String adminInstallUpdate(String version) {
    return 'Instalar actualización (v$version)';
  }

  @override
  String adminCatalogLoadFailed(String error) {
    return 'No se pudo cargar el catálogo: $error';
  }

  @override
  String get adminNoPackagesMatchSearch =>
      'Ningún paquete coincide con tu búsqueda';

  @override
  String get adminNoPackagesAvailable => 'No hay paquetes disponibles';

  @override
  String get adminExperimentalIntegration => 'Integración experimental';

  @override
  String get adminExperimentalWarning =>
      'La integración de ajustes de complementos es aún experimental. Algunas páginas de ajustes pueden no mostrarse correctamente.';

  @override
  String get continueAction => 'Continuar';

  @override
  String adminPluginRemoveAfterRestart(String name) {
    return '\"$name\" se eliminará después de reiniciar el servidor';
  }

  @override
  String adminUninstallFailed(String error) {
    return 'No se pudo desinstalar: $error';
  }

  @override
  String adminPluginUpdating(String name, String version) {
    return 'Actualizando \"$name\" a v$version...';
  }

  @override
  String adminPluginLoadFailed(String error) {
    return 'No se pudo cargar el complemento: $error';
  }

  @override
  String get adminPluginNotFound => 'Complemento no encontrado';

  @override
  String adminPluginVersion(String version) {
    return 'Versión $version';
  }

  @override
  String get adminEnablePlugin => 'Activar complemento';

  @override
  String get adminPluginSettingsPage => 'Página de ajustes del complemento';

  @override
  String get adminRevisionHistory => 'Historial de revisiones';

  @override
  String get adminNoChangelog => 'No hay registro de cambios disponible.';

  @override
  String get adminRemoveRepository => 'Eliminar repositorio';

  @override
  String adminRemoveRepositoryConfirm(String name) {
    return '¿Seguro que quieres eliminar «$name»?';
  }

  @override
  String adminRepositoriesSaveFailed(String error) {
    return 'No se pudieron guardar los repositorios: $error';
  }

  @override
  String adminRepositoriesLoadFailed(String error) {
    return 'No se pudieron cargar los repositorios: $error';
  }

  @override
  String get adminRepositoryNameHint => 'p. ej. Jellyfin Stable';

  @override
  String get adminRepositoryUrl => 'URL del repositorio';

  @override
  String get adminAddEntry => 'Añadir entrada';

  @override
  String get adminInvalidUrl => 'URL no válida';

  @override
  String adminPluginSettingsLoadFailed(String error) {
    return 'No se pueden cargar los ajustes del complemento: $error';
  }

  @override
  String adminCouldNotOpenUrl(String uri) {
    return 'No se pudo abrir $uri';
  }

  @override
  String get adminOpenInBrowser => 'Abrir en el navegador';

  @override
  String get adminOpenExternally => 'Abrir externamente';

  @override
  String get adminGeneralSettings => 'Ajustes generales';

  @override
  String get adminServerName => 'Nombre del servidor';

  @override
  String get adminPreferredMetadataCountry => 'País de metadatos preferido';

  @override
  String get adminCachePath => 'Ruta de caché';

  @override
  String get adminMetadataPath => 'Ruta de metadatos';

  @override
  String get adminLibraryScanConcurrency =>
      'Concurrencia de escaneo de bibliotecas';

  @override
  String get adminParallelImageEncodingLimit =>
      'Límite de codificación de imágenes en paralelo';

  @override
  String get adminSlowResponseThreshold => 'Umbral de respuesta lenta (ms)';

  @override
  String get adminBrandingLoadFailed => 'Error al cargar los ajustes de marca';

  @override
  String get adminLoginDisclaimer => 'Aviso legal de inicio de sesión';

  @override
  String get adminLoginDisclaimerHint =>
      'HTML que se muestra debajo del formulario de inicio de sesión';

  @override
  String get adminCustomCss => 'CSS personalizado';

  @override
  String get adminCustomCssHint =>
      'CSS personalizado aplicado a la interfaz web';

  @override
  String get adminEnableSplashScreen => 'Activar pantalla de bienvenida';

  @override
  String get adminStreamingLoadFailed =>
      'Error al cargar los ajustes de transmisión';

  @override
  String get adminStreamingDescription =>
      'Establece los límites globales de tasa de bits para las conexiones remotas.';

  @override
  String get adminRemoteBitrateLimitMbps =>
      'Límite de tasa de bits del cliente remoto (Mbps)';

  @override
  String get adminLeaveEmptyForUnlimited =>
      'Déjalo vacío o en 0 para no tener límite';

  @override
  String get adminPlaybackLoadFailed =>
      'Error al cargar los ajustes de reproducción';

  @override
  String get adminHardwareAcceleration => 'Aceleración por hardware';

  @override
  String get adminVaapiDevice => 'Dispositivo VA-API';

  @override
  String get adminEnableHardwareEncoding => 'Activar codificación por hardware';

  @override
  String get adminEnableHardwareDecoding =>
      'Activar decodificación por hardware para:';

  @override
  String get adminEncodingThreads => 'Hilos de codificación';

  @override
  String get adminAutomatic => '0 = automático';

  @override
  String get adminTranscodingTempPath => 'Ruta temporal de transcodificación';

  @override
  String get adminEnableFallbackFont => 'Activar fuente alternativa';

  @override
  String get adminFallbackFontPath => 'Ruta de fuente alternativa';

  @override
  String get adminAllowSegmentDeletion => 'Permitir eliminación de segmentos';

  @override
  String get adminSegmentKeepSeconds => 'Conservar segmentos (segundos)';

  @override
  String get adminThrottleBuffering => 'Limitar el búfer';

  @override
  String get adminTrickplayLoadFailed =>
      'Error al cargar los ajustes de Trickplay';

  @override
  String get adminEnableHardwareAcceleration =>
      'Activar aceleración por hardware';

  @override
  String get adminEnableKeyFrameExtraction =>
      'Activar la extracción solo de fotogramas clave';

  @override
  String get adminKeyFrameSubtitle => 'Más rápido pero menos preciso';

  @override
  String get adminScanBehavior => 'Comportamiento de escaneo';

  @override
  String get adminProcessPriority => 'Prioridad del proceso';

  @override
  String get adminImageSettings => 'Ajustes de imagen';

  @override
  String get adminIntervalMs => 'Intervalo (ms)';

  @override
  String get adminCaptureFrameSubtitle =>
      'Con qué frecuencia capturar fotogramas';

  @override
  String get adminWidthResolutions => 'Resoluciones de ancho';

  @override
  String get adminTileWidth => 'Ancho del mosaico';

  @override
  String get adminTileHeight => 'Alto del mosaico';

  @override
  String get adminQualitySubtitle =>
      'Valores más bajos = mejor calidad, archivos más grandes';

  @override
  String get adminProcessThreads => 'Hilos de proceso';

  @override
  String get adminResumeLoadFailed =>
      'Error al cargar los ajustes de reanudación';

  @override
  String get adminResumeDescription =>
      'Configura cuándo se marca el contenido como reproducido en parte o por completo.';

  @override
  String get adminMinResumePercentage => 'Porcentaje mínimo de reanudación';

  @override
  String get adminMinResumeSubtitle =>
      'El contenido debe reproducirse más allá de este porcentaje para guardar el progreso';

  @override
  String get adminMaxResumePercentage => 'Porcentaje máximo de reanudación';

  @override
  String get adminMaxResumeSubtitle =>
      'El contenido se considera completamente reproducido después de este porcentaje';

  @override
  String get adminMinResumeDuration =>
      'Duración mínima de reanudación (segundos)';

  @override
  String get adminMinResumeDurationSubtitle =>
      'Los elementos de menor duración no se pueden reanudar';

  @override
  String get adminMinAudiobookResume =>
      'Porcentaje mínimo de reanudación de audiolibros';

  @override
  String get adminMaxAudiobookResume =>
      'Porcentaje máximo de reanudación de audiolibros';

  @override
  String get adminNetworkingLoadFailed => 'Error al cargar los ajustes de red';

  @override
  String get adminNetworkingWarning =>
      'Los cambios en los ajustes de red pueden requerir un reinicio del servidor.';

  @override
  String get adminEnableRemoteAccess => 'Activar acceso remoto';

  @override
  String get ports => 'Puertos';

  @override
  String get adminHttpPort => 'Puerto HTTP';

  @override
  String get adminHttpsPort => 'Puerto HTTPS';

  @override
  String get adminPublicHttpsPort => 'Puerto HTTPS público';

  @override
  String get adminBaseUrl => 'URL base';

  @override
  String get adminBaseUrlHint => 'p. ej. /jellyfin';

  @override
  String get https => 'HTTPS';

  @override
  String get adminEnableHttps => 'Activar HTTPS';

  @override
  String get adminLocalNetwork => 'Red local';

  @override
  String get adminLocalNetworkAddresses => 'Direcciones de red local';

  @override
  String get adminKnownProxies => 'Proxies conocidos';

  @override
  String get adminRemoteIpFilter => 'Filtro de IP remota';

  @override
  String get adminRemoteIpFilterEntries => 'Filtro de IP remota';

  @override
  String get adminCertificatePath => 'Ruta del certificado';

  @override
  String get whitelist => 'Lista blanca';

  @override
  String get notSet => 'No establecido';

  @override
  String adminMetadataLoadFailed(String error) {
    return 'No se pudieron cargar los metadatos: $error';
  }

  @override
  String get adminRefreshMetadata => 'Actualizar metadatos';

  @override
  String get recursive => 'Recursivo';

  @override
  String get adminReplaceAllMetadata => 'Reemplazar todos los metadatos';

  @override
  String get adminMetadataRefreshRequested =>
      'Actualización de metadatos solicitada';

  @override
  String adminMetadataRefreshFailed(String error) {
    return 'No se pudieron actualizar los metadatos: $error';
  }

  @override
  String get adminNoRemoteMatches => 'No se encontraron coincidencias remotas';

  @override
  String get adminRemoteResults => 'Resultados remotos';

  @override
  String get adminRemoteMetadataApplied => 'Metadatos remotos aplicados';

  @override
  String adminRemoteSearchFailed(String error) {
    return 'Ha fallado la búsqueda remota: $error';
  }

  @override
  String get adminUpdateContentType => 'Actualizar tipo de contenido';

  @override
  String get adminContentType => 'Tipo de contenido';

  @override
  String get adminContentTypeUpdated => 'Tipo de contenido actualizado';

  @override
  String adminContentTypeUpdateFailed(String error) {
    return 'No se pudo actualizar el tipo de contenido: $error';
  }

  @override
  String get adminMetadataEditorLoadFailed =>
      'Error al cargar el editor de metadatos';

  @override
  String get adminNoPeopleEntries => 'No hay entradas de personas';

  @override
  String get adminNoExternalIds =>
      'No hay identificadores externos disponibles';

  @override
  String adminImageUpdated(String imageType) {
    return 'Imagen $imageType actualizada';
  }

  @override
  String adminImageDownloadFailed(String error) {
    return 'No se pudo descargar la imagen: $error';
  }

  @override
  String get adminUnsupportedImageFormat => 'Formato de imagen no compatible';

  @override
  String get adminImageReadFailed => 'Error al leer la imagen seleccionada';

  @override
  String adminImageUploaded(String imageType) {
    return 'Imagen $imageType subida';
  }

  @override
  String adminImageUploadFailed(String error) {
    return 'No se pudo subir la imagen: $error';
  }

  @override
  String adminDeleteImage(String imageType) {
    return 'Eliminar imagen $imageType';
  }

  @override
  String adminImageDeleted(String imageType) {
    return 'Imagen $imageType eliminada';
  }

  @override
  String adminImageDeleteFailed(String error) {
    return 'No se pudo eliminar la imagen: $error';
  }

  @override
  String get adminAllProviders => 'Todos los proveedores';

  @override
  String get adminNoRemoteImages => 'No se encontraron imágenes remotas';

  @override
  String adminTunerDiscoveryFailed(String error) {
    return 'Ha fallado la búsqueda de sintonizadores: $error';
  }

  @override
  String get adminTunerTypeM3u => 'Sintonizador M3U';

  @override
  String get adminTunerTypeHdHomerun => 'HDHomeRun';

  @override
  String get adminTunerFileOrUrl => 'Archivo o URL';

  @override
  String get adminTunerIpAddress => 'Dirección IP del sintonizador';

  @override
  String get adminTunerFriendlyName => 'Nombre descriptivo';

  @override
  String get adminTunerUserAgent => 'Agente de usuario';

  @override
  String get adminTunerCount => 'Límite de conexiones simultáneas';

  @override
  String get adminTunerCountHelp =>
      'Número máximo de flujos que el sintonizador permite a la vez. Pon 0 para que no haya límite.';

  @override
  String get adminTunerFallbackBitrate =>
      'Tasa de bits máxima alternativa de transmisión';

  @override
  String get adminTunerImportFavoritesOnly =>
      'Importar solo los canales favoritos';

  @override
  String get adminTunerAllowHwTranscoding =>
      'Permitir la transcodificación por hardware';

  @override
  String get adminTunerAllowFmp4 =>
      'Permitir el contenedor de transcodificación fMP4';

  @override
  String get adminTunerAllowStreamSharing => 'Permitir compartir flujos';

  @override
  String get adminTunerEnableStreamLooping => 'Activar la repetición del flujo';

  @override
  String get adminTunerIgnoreDts => 'Ignorar DTS';

  @override
  String get adminTunerReadAtNativeFramerate =>
      'Leer la entrada a la velocidad de fotogramas nativa';

  @override
  String get adminProviderXmltv => 'XMLTV';

  @override
  String get adminProviderSchedulesDirect => 'Schedules Direct';

  @override
  String get adminXmltvPath => 'Archivo o URL';

  @override
  String get adminXmltvMoviePrefix => 'Prefijo de película';

  @override
  String get adminXmltvMovieCategories => 'Categorías de películas';

  @override
  String get adminXmltvCategoriesHelp =>
      'Separa varias categorías con una barra vertical.';

  @override
  String get adminXmltvKidsCategories => 'Categorías infantiles';

  @override
  String get adminXmltvNewsCategories => 'Categorías de noticias';

  @override
  String get adminXmltvSportsCategories => 'Categorías de deportes';

  @override
  String get adminSdUsername => 'Nombre de usuario';

  @override
  String get adminSdPassword => 'Contraseña';

  @override
  String get adminSdCountry => 'País';

  @override
  String get adminSdCountrySelect => 'Selecciona un país';

  @override
  String get adminSdPostalCode => 'Código postal';

  @override
  String get adminEnableAllTuners => 'Activar todos los sintonizadores';

  @override
  String adminTunerRemoveFailed(String error) {
    return 'No se pudo eliminar el sintonizador: $error';
  }

  @override
  String adminProviderRemoveFailed(String error) {
    return 'No se pudo eliminar el proveedor: $error';
  }

  @override
  String get adminSeriesRecordingPath => 'Ruta de grabación de series';

  @override
  String get adminMovieRecordingPath => 'Ruta de grabación de películas';

  @override
  String get adminGuideDaysAuto => 'Automático';

  @override
  String get adminRecordingPostProcessor =>
      'Ruta de la aplicación de posprocesamiento';

  @override
  String get adminRecordingPostProcessorArgs => 'Argumentos del posprocesador';

  @override
  String get adminSaveRecordingNfo =>
      'Guardar los metadatos NFO de las grabaciones';

  @override
  String get adminSaveRecordingImages =>
      'Guardar las imágenes de las grabaciones';

  @override
  String get adminLiveTvSectionPaths => 'Rutas de grabación';

  @override
  String get adminLiveTvSectionPostProcessing => 'Posprocesamiento';

  @override
  String adminSettingsSaveFailed(String error) {
    return 'No se pudieron guardar los ajustes: $error';
  }

  @override
  String get adminLiveTvLoadFailed =>
      'Error al cargar la administración de TV en directo';

  @override
  String get adminTunerDevices => 'Dispositivos sintonizadores';

  @override
  String get adminNoTunerHosts => 'No hay hosts de sintonizador configurados';

  @override
  String get adminGuideProviders => 'Proveedores de guía';

  @override
  String get adminGuideRefreshStarted =>
      'Actualización de los datos de la guía iniciada';

  @override
  String get adminGuideRefreshUnavailable =>
      'La tarea de actualización de la guía no está disponible en este servidor.';

  @override
  String get adminNoListingProviders =>
      'No hay proveedores de listados configurados';

  @override
  String get adminSettingsSaved => 'Ajustes guardados';

  @override
  String get adminBackupsNotAvailable =>
      'Las copias de seguridad no están disponibles en esta versión del servidor.';

  @override
  String get adminRestoreWarning1 =>
      'La restauración reemplazará TODOS los datos actuales del servidor por los de la copia de seguridad.';

  @override
  String get adminRestoreWarning2 =>
      'Se sobrescribirán los ajustes del servidor, los usuarios y los datos de bibliotecas actuales.';

  @override
  String get adminRestoreWarning3 =>
      'El servidor se reiniciará después de la restauración.';

  @override
  String adminRestoreConfirmMessage(String name) {
    return '¿Restaurar la copia de seguridad $name ahora?';
  }

  @override
  String get adminBackupsTitle => 'Copias de seguridad';

  @override
  String get adminUnknownDate => 'Fecha desconocida';

  @override
  String get adminUnnamedBackup => 'Copia de seguridad sin nombre';

  @override
  String get adminApply => 'Aplicar';

  @override
  String get adminLogsTitle => 'Registros del servidor';

  @override
  String get adminLogsNewestFirst => 'Más reciente primero';

  @override
  String get adminLogsOldestFirst => 'Más antiguo primero';

  @override
  String get adminLogsJustNow => 'Ahora mismo';

  @override
  String adminLogsMinutesAgo(int minutes) {
    return 'hace $minutes min';
  }

  @override
  String adminLogsHoursAgo(int hours) {
    return 'hace $hours h';
  }

  @override
  String adminLogsDaysAgo(int days) {
    return 'hace $days d';
  }

  @override
  String adminLogViewerLoadFailed(String fileName) {
    return 'No se pudo cargar $fileName';
  }

  @override
  String adminLogViewerMatches(int count) {
    return '$count coincidencias';
  }

  @override
  String get adminLogViewerNoMatches => 'No hay líneas coincidentes';

  @override
  String get adminMetadataEditorTitle => 'Editor de metadatos';

  @override
  String get adminMetadataIdentify => 'Identificar';

  @override
  String get adminMetadataType => 'Tipo';

  @override
  String get adminMetadataDetails => 'Detalles';

  @override
  String get adminMetadataExternalIds => 'IDs externos';

  @override
  String get adminMetadataImages => 'Imágenes';

  @override
  String get adminMetadataFieldTitle => 'Título';

  @override
  String get adminMetadataFieldSortTitle => 'Título de ordenación';

  @override
  String get adminMetadataFieldOriginalTitle => 'Título original';

  @override
  String get adminMetadataFieldPremiereDate => 'Fecha de estreno (AAAA-MM-DD)';

  @override
  String get adminMetadataFieldEndDate => 'Fecha de finalización (AAAA-MM-DD)';

  @override
  String get adminMetadataFieldProductionYear => 'Año de producción';

  @override
  String get adminMetadataFieldOfficialRating => 'Clasificación oficial';

  @override
  String get adminMetadataFieldCommunityRating => 'Valoración de la comunidad';

  @override
  String get adminMetadataFieldCriticRating => 'Valoración de la crítica';

  @override
  String get adminMetadataFieldCustomRating => 'Clasificación personalizada';

  @override
  String get adminMetadataFieldTagline => 'Eslogan';

  @override
  String get adminMetadataFieldOverview => 'Sinopsis';

  @override
  String get adminMetadataFieldDisplayOrder => 'Orden de visualización';

  @override
  String get adminMetadataDisplayOrderAired => 'Emisión';

  @override
  String get adminMetadataDisplayOrderOriginalAirDate =>
      'Fecha de emisión original';

  @override
  String get adminMetadataDisplayOrderAbsolute => 'Absoluto';

  @override
  String get adminMetadataDisplayOrderDvd => 'DVD';

  @override
  String get adminMetadataDisplayOrderDigital => 'Digital';

  @override
  String get adminMetadataDisplayOrderStoryArc => 'Arco argumental';

  @override
  String get adminMetadataDisplayOrderProduction => 'Producción';

  @override
  String get adminMetadataDisplayOrderTv => 'TV';

  @override
  String get adminMetadataDisplayOrderAlternate => 'Alternativo';

  @override
  String get adminMetadataDisplayOrderRegional => 'Regional';

  @override
  String get adminMetadataDisplayOrderAlternateDvd => 'DVD alternativo';

  @override
  String get adminMetadataDisplayOrderDateModified => 'Fecha de modificación';

  @override
  String get adminMetadataDisplayOrderSortName => 'Nombre de ordenación';

  @override
  String get adminMetadataDisplayOrderReleaseDate => 'Fecha de estreno';

  @override
  String get adminMetadataSettings => 'Ajustes de metadatos';

  @override
  String get adminMetadataDownloadLanguage => 'Idioma de descarga preferido';

  @override
  String get adminMetadataCountryRegion => 'País/región';

  @override
  String get adminMetadataInheritHelp =>
      'Déjalo en Predeterminado para heredar el ajuste de un elemento superior o el valor predeterminado del servidor.';

  @override
  String get adminMetadataField3DFormat => 'Formato 3D';

  @override
  String get adminMetadataPersonKindActor => 'Actor';

  @override
  String get adminMetadataPersonKindDirector => 'Director';

  @override
  String get adminMetadataPersonKindComposer => 'Compositor';

  @override
  String get adminMetadataPersonKindWriter => 'Guionista';

  @override
  String get adminMetadataPersonKindGuestStar => 'Estrella invitada';

  @override
  String get adminMetadataPersonKindProducer => 'Productor';

  @override
  String get adminMetadataPersonKindConductor => 'Director de orquesta';

  @override
  String get adminMetadataPersonKindLyricist => 'Letrista';

  @override
  String get adminMetadataPersonKindArranger => 'Arreglista';

  @override
  String get adminMetadataPersonKindEngineer => 'Ingeniero';

  @override
  String get adminMetadataPersonKindMixer => 'Mezclador';

  @override
  String get adminMetadataPersonKindRemixer => 'Remezclador';

  @override
  String get adminMetadataPersonKindCreator => 'Creador';

  @override
  String get adminMetadataPersonKindArtist => 'Artista';

  @override
  String get adminMetadataPersonKindAlbumArtist => 'Artista del álbum';

  @override
  String get adminMetadataPersonKindAuthor => 'Autor';

  @override
  String get adminMetadataPersonKindIllustrator => 'Ilustrador';

  @override
  String get adminMetadataPersonKindPenciller => 'Dibujante';

  @override
  String get adminMetadataPersonKindInker => 'Entintador';

  @override
  String get adminMetadataPersonKindColorist => 'Colorista';

  @override
  String get adminMetadataPersonKindLetterer => 'Rotulista';

  @override
  String get adminMetadataPersonKindCoverArtist => 'Portadista';

  @override
  String get adminMetadataPersonKindEditor => 'Editor';

  @override
  String get adminMetadataPersonKindTranslator => 'Traductor';

  @override
  String get adminMetadataPersonKindNarrator => 'Narrador';

  @override
  String get adminMetadataAirDays => 'Días de emisión';

  @override
  String get adminMetadataLockItem =>
      'Bloquear este elemento para impedir futuros cambios en los metadatos';

  @override
  String get adminMetadataEnabledFields => 'Campos activados';

  @override
  String get adminMetadataEnabledFieldsHelp =>
      'Desmarca un campo para bloquearlo e impedir que se cambien sus datos.';

  @override
  String get adminMetadataLockFieldName => 'Nombre';

  @override
  String get adminMetadataLockFieldOverview => 'Sinopsis';

  @override
  String get adminMetadataLockFieldGenres => 'Géneros';

  @override
  String get adminMetadataLockFieldOfficialRating => 'Clasificación por edades';

  @override
  String get adminMetadataLockFieldCast => 'Personas';

  @override
  String get adminMetadataLockFieldProductionLocations =>
      'Lugares de producción';

  @override
  String get adminMetadataLockFieldBirthLocation => 'Lugar de nacimiento';

  @override
  String get adminMetadataLockFieldRuntime => 'Duración';

  @override
  String get adminMetadataLockFieldStudios => 'Estudios';

  @override
  String get adminMetadataLockFieldTags => 'Etiquetas';

  @override
  String get adminMetadataGenres => 'Géneros';

  @override
  String get adminMetadataTags => 'Etiquetas';

  @override
  String get adminMetadataStudios => 'Estudios';

  @override
  String get adminMetadataPeople => 'Personas';

  @override
  String get adminMetadataAddGenre => 'Añadir género';

  @override
  String get adminMetadataAddTag => 'Añadir etiqueta';

  @override
  String get adminMetadataAddStudio => 'Añadir estudio';

  @override
  String get adminMetadataAddPerson => 'Añadir persona';

  @override
  String get adminMetadataEditPerson => 'Editar persona';

  @override
  String get adminMetadataRole => 'Rol';

  @override
  String get adminMetadataImagePrimary => 'Principal';

  @override
  String get adminMetadataImageBackdrop => 'Fondo';

  @override
  String get adminMetadataImageLogo => 'Logotipo';

  @override
  String get adminMetadataImageBanner => 'Banner';

  @override
  String get adminMetadataImageThumb => 'Miniatura';

  @override
  String get adminMetadataProvider => 'Proveedor';

  @override
  String adminMetadataImageUpdated(String imageType) {
    return 'Imagen $imageType actualizada';
  }

  @override
  String adminMetadataImageUploaded(String imageType) {
    return 'Imagen $imageType subida';
  }

  @override
  String adminMetadataImageDeleted(String imageType) {
    return 'Imagen $imageType eliminada';
  }

  @override
  String adminMetadataImageDownloadFailed(String error) {
    return 'No se pudo descargar la imagen: $error';
  }

  @override
  String get adminMetadataImageReadFailed =>
      'Error al leer la imagen seleccionada';

  @override
  String adminMetadataImageUploadFailed(String error) {
    return 'No se pudo subir la imagen: $error';
  }

  @override
  String adminMetadataDeleteImageTitle(String imageType) {
    return 'Eliminar imagen $imageType';
  }

  @override
  String get adminMetadataDeleteImageContent =>
      'Esto elimina la imagen actual del elemento.';

  @override
  String adminMetadataImageDeleteFailed(String error) {
    return 'No se pudo eliminar la imagen: $error';
  }

  @override
  String adminMetadataChooseImage(String imageType) {
    return 'Elige la imagen $imageType';
  }

  @override
  String get adminMetadataUpload => 'Subir';

  @override
  String get adminMetadataUpdate => 'Actualizar';

  @override
  String get adminMetadataRemoteImage => 'Imagen remota';

  @override
  String get adminPluginsInstalled => 'Instalados';

  @override
  String get adminPluginsCatalog => 'Catálogo';

  @override
  String get adminPluginsActive => 'Activos';

  @override
  String get adminPluginsRestart => 'Reiniciar';

  @override
  String get adminPluginsRestartRequired => 'Requieren reinicio';

  @override
  String get adminPluginsNoSearchResults =>
      'Ningún complemento coincide con tu búsqueda';

  @override
  String get adminPluginsNoneInstalled => 'No hay complementos instalados';

  @override
  String get adminPluginsNoneActive => 'No hay complementos activos';

  @override
  String get adminPluginsNoneRequireRestart =>
      'Ningún complemento requiere reiniciar el servidor';

  @override
  String adminPluginsUpdateAvailable(String version) {
    return 'Actualización disponible: v$version';
  }

  @override
  String get adminPluginsUpdateAvailableGeneric => 'Actualización disponible';

  @override
  String get adminPluginsPendingRemoval =>
      'Eliminación pendiente tras reinicio';

  @override
  String get adminPluginsChangesPending => 'Cambios pendientes de reinicio';

  @override
  String get adminPluginsEnable => 'Activar';

  @override
  String get adminPluginsDisable => 'Desactivar';

  @override
  String get adminPluginsInstallUpdate => 'Instalar actualización';

  @override
  String adminPluginsInstallUpdateVersioned(String version) {
    return 'Instalar actualización (v$version)';
  }

  @override
  String get adminPluginsCatalogNoSearchResults =>
      'Ningún paquete coincide con tu búsqueda';

  @override
  String get adminPluginsCatalogEmpty => 'No hay paquetes disponibles';

  @override
  String adminPluginsInstalling(String name) {
    return '\"$name\" se está instalando...';
  }

  @override
  String get adminPluginDetailExperimental => 'Integración experimental';

  @override
  String get adminPluginDetailExperimentalContent =>
      'La integración de ajustes de complementos es aún experimental. Algunos campos o diseños pueden no mostrarse correctamente.';

  @override
  String get adminPluginDetailToggle404 =>
      'No se pudo activar o desactivar el complemento. El servidor no encuentra esta versión del complemento. Actualiza la lista de complementos y vuelve a intentarlo.';

  @override
  String get adminPluginDetailToggleDioError =>
      'No se pudo activar o desactivar el complemento. Consulta los registros del servidor para ver más detalles.';

  @override
  String adminPluginDetailSettingsTitle(String name) {
    return 'Ajustes de $name';
  }

  @override
  String get adminPluginDetailDetails => 'Detalles';

  @override
  String get adminPluginDetailDeveloper => 'Desarrollador';

  @override
  String get adminPluginDetailRepository => 'Repositorio';

  @override
  String get adminPluginDetailBundled => 'Incluido';

  @override
  String get adminPluginDetailEnablePlugin => 'Activar complemento';

  @override
  String get adminPluginDetailRestartRequired =>
      'Se requiere un reinicio del servidor para que los cambios surtan efecto.';

  @override
  String get adminPluginDetailRemovalPending =>
      'Este complemento se eliminará tras reiniciar el servidor.';

  @override
  String get adminPluginDetailMalfunctioned =>
      'Este complemento ha fallado y puede que no funcione bien.';

  @override
  String get adminPluginDetailNotSupported =>
      'Este complemento no es compatible con la versión actual del servidor.';

  @override
  String get adminPluginDetailSuperseded =>
      'Este complemento ha sido reemplazado por una versión más nueva.';

  @override
  String adminReposLoadFailed(String error) {
    return 'No se pudieron cargar los repositorios: $error';
  }

  @override
  String get adminReposRemoveTitle => 'Eliminar repositorio';

  @override
  String adminReposRemoveConfirm(String name) {
    return '¿Seguro que quieres eliminar \"$name\"?';
  }

  @override
  String get adminReposRemove => 'Quitar';

  @override
  String adminReposSaveFailed(String error) {
    return 'No se pudieron guardar los repositorios: $error';
  }

  @override
  String get adminReposEmpty => 'No hay repositorios configurados';

  @override
  String get adminReposEmptySubtitle =>
      'Añade un repositorio para explorar los complementos disponibles';

  @override
  String get adminReposUnnamed => '(sin nombre)';

  @override
  String get adminReposEditTitle => 'Editar repositorio';

  @override
  String get adminReposAddTitle => 'Añadir repositorio';

  @override
  String get adminReposUrl => 'URL del repositorio';

  @override
  String get adminReposNameHint => 'p. ej. Jellyfin Stable';

  @override
  String get adminPluginSettingsInvalidUrl => 'URL no válida';

  @override
  String get adminGeneralSettingsTitle => 'Ajustes generales';

  @override
  String get adminGeneralMetadataLanguage => 'Idioma de metadatos preferido';

  @override
  String get adminGeneralMetadataLanguageHint => 'p. ej. en, de, fr';

  @override
  String get adminGeneralMetadataCountry => 'País de metadatos preferido';

  @override
  String get adminGeneralMetadataCountryHint => 'p. ej. US, DE, FR';

  @override
  String get adminGeneralLibraryScanConcurrency =>
      'Concurrencia de escaneo de bibliotecas';

  @override
  String get adminGeneralImageEncodingLimit =>
      'Límite de codificación de imágenes en paralelo';

  @override
  String get adminUnknownError => 'Error desconocido';

  @override
  String get adminBrowse => 'Explorar';

  @override
  String get adminCloseBrowser => 'Cerrar explorador';

  @override
  String get adminNetworkingTitle => 'Redes';

  @override
  String get adminNetworkingRestartWarning =>
      'Los cambios en los ajustes de red pueden requerir un reinicio del servidor.';

  @override
  String get adminNetworkingEnableHttps => 'Activar HTTPS';

  @override
  String get adminNetworkingAddressHint => 'p. ej. 192.168.1.0/24';

  @override
  String get adminNetworkingKnownProxies => 'Proxies conocidos';

  @override
  String get adminNetworkingProxyHint => 'p. ej. 10.0.0.1';

  @override
  String get adminNetworkingWhitelist => 'Lista blanca';

  @override
  String get adminNetworkingBlacklist => 'Lista negra';

  @override
  String get adminNetworkingAddEntry => 'Añadir entrada';

  @override
  String get adminBrandingTitle => 'Marca';

  @override
  String get adminBrandingLoginDisclaimer => 'Aviso legal de inicio de sesión';

  @override
  String get adminBrandingLoginDisclaimerHint =>
      'HTML que se muestra debajo del formulario de inicio de sesión';

  @override
  String get adminBrandingCustomCss => 'CSS personalizado';

  @override
  String get adminBrandingCustomCssHint =>
      'CSS personalizado aplicado a la interfaz web';

  @override
  String get adminBrandingEnableSplash => 'Activar pantalla de bienvenida';

  @override
  String get adminBrandingSplashUpload => 'Subir imagen';

  @override
  String get adminBrandingSplashUploaded =>
      'Pantalla de bienvenida actualizada';

  @override
  String get adminBrandingSplashUploadFailed =>
      'Error al subir la pantalla de bienvenida';

  @override
  String get adminBrandingSplashDeleted => 'Pantalla de bienvenida eliminada';

  @override
  String get adminBrandingNoSplash =>
      'Sin pantalla de bienvenida personalizada';

  @override
  String get adminPlaybackHwAccel => 'Aceleración por hardware';

  @override
  String get adminPlaybackHwAccelLabel => 'Aceleración por hardware';

  @override
  String get adminPlaybackEnableHwEncoding =>
      'Activar codificación por hardware';

  @override
  String get adminPlaybackQsvDevice => 'Dispositivo QSV';

  @override
  String get adminPlaybackEnhancedNvdec =>
      'Activar el decodificador NVDEC mejorado';

  @override
  String get adminPlaybackPreferNativeDecoder =>
      'Preferir el decodificador de hardware nativo del sistema';

  @override
  String get adminPlaybackColorDepth10Hevc => 'Decodificación HEVC de 10 bits';

  @override
  String get adminPlaybackColorDepth10Vp9 => 'Decodificación VP9 de 10 bits';

  @override
  String get adminPlaybackColorDepth10HevcRext =>
      'Decodificación HEVC RExt de 8/10 bits';

  @override
  String get adminPlaybackColorDepth12HevcRext =>
      'Decodificación HEVC RExt de 12 bits';

  @override
  String get adminPlaybackHwEncodingSection => 'Codificación por hardware';

  @override
  String get adminPlaybackAllowHevcEncoding => 'Permitir la codificación HEVC';

  @override
  String get adminPlaybackAllowAv1Encoding => 'Permitir la codificación AV1';

  @override
  String get adminPlaybackIntelLowPowerH264 =>
      'Activar el codificador H.264 de bajo consumo de Intel';

  @override
  String get adminPlaybackIntelLowPowerHevc =>
      'Activar el codificador HEVC de bajo consumo de Intel';

  @override
  String get adminPlaybackToneMapping => 'Mapeo de tonos';

  @override
  String get adminPlaybackEnableTonemapping => 'Activar el mapeo de tonos';

  @override
  String get adminPlaybackEnableVppTonemapping =>
      'Activar el mapeo de tonos VPP';

  @override
  String get adminPlaybackEnableVtTonemapping =>
      'Activar el mapeo de tonos de VideoToolbox';

  @override
  String get adminPlaybackTonemappingAlgorithm => 'Algoritmo de mapeo de tonos';

  @override
  String get adminPlaybackTonemappingMode => 'Modo de mapeo de tonos';

  @override
  String get adminPlaybackTonemappingRange => 'Rango de mapeo de tonos';

  @override
  String get adminPlaybackTonemappingDesat => 'Desaturación del mapeo de tonos';

  @override
  String get adminPlaybackTonemappingPeak => 'Pico del mapeo de tonos';

  @override
  String get adminPlaybackTonemappingParam => 'Parámetro del mapeo de tonos';

  @override
  String get adminPlaybackVppTonemappingBrightness =>
      'Brillo del mapeo de tonos VPP';

  @override
  String get adminPlaybackVppTonemappingContrast =>
      'Contraste del mapeo de tonos VPP';

  @override
  String get adminPlaybackEncoderPreset => 'Preajuste del codificador';

  @override
  String get adminPlaybackH264Crf => 'CRF de codificación H.264';

  @override
  String get adminPlaybackH265Crf => 'CRF de codificación H.265 (HEVC)';

  @override
  String get adminPlaybackDeinterlaceMethod => 'Método de desentrelazado';

  @override
  String get adminPlaybackDeinterlaceDoubleRate =>
      'Duplicar la velocidad de fotogramas al desentrelazar';

  @override
  String get adminPlaybackAudioSection => 'Audio';

  @override
  String get adminPlaybackEnableAudioVbr =>
      'Activar la codificación de audio VBR';

  @override
  String get adminPlaybackDownmixBoost => 'Ganancia de la mezcla de audio';

  @override
  String get adminPlaybackDownmixAlgorithm => 'Algoritmo de mezcla a estéreo';

  @override
  String get adminPlaybackMaxMuxingQueue =>
      'Tamaño máximo de la cola de multiplexación';

  @override
  String get adminPlaybackAutoOption => 'Automático';

  @override
  String get adminPlaybackEncoding => 'Codificación';

  @override
  String get adminPlaybackEncodingThreads => 'Hilos de codificación';

  @override
  String get adminPlaybackFallbackFont => 'Activar fuente alternativa';

  @override
  String get adminPlaybackFallbackFontPath => 'Ruta de fuente alternativa';

  @override
  String get adminPlaybackStreaming => 'Transmisión';

  @override
  String get adminResumeVideo => 'Vídeo';

  @override
  String get adminResumeAudiobooks => 'Audiolibros';

  @override
  String get adminStreamingBitrateLimit =>
      'Límite de tasa de bits del cliente remoto (Mbps)';

  @override
  String get adminStreamingBitrateLimitHint =>
      'Déjalo vacío o en 0 para no poner límite';

  @override
  String get adminTrickplayHwAccel => 'Activar aceleración por hardware';

  @override
  String get adminTrickplayHwEncoding => 'Activar codificación por hardware';

  @override
  String get adminTrickplayKeyFrameOnly =>
      'Activar extracción solo de fotogramas clave';

  @override
  String get adminTrickplayKeyFrameOnlySubtitle =>
      'Más rápido, pero menos preciso';

  @override
  String get adminTrickplayNonBlocking => 'No bloqueante';

  @override
  String get adminTrickplayBlocking => 'Bloqueante';

  @override
  String get adminTrickplayPriorityHigh => 'Alta';

  @override
  String get adminTrickplayPriorityAboveNormal => 'Por encima de lo normal';

  @override
  String get adminTrickplayPriorityNormal => 'Normal';

  @override
  String get adminTrickplayPriorityBelowNormal => 'Por debajo de lo normal';

  @override
  String get adminTrickplayPriorityIdle => 'Inactivo';

  @override
  String get adminTrickplayImageSettings => 'Ajustes de imagen';

  @override
  String get adminTrickplayInterval => 'Intervalo (ms)';

  @override
  String get adminTrickplayIntervalSubtitle =>
      'Con qué frecuencia capturar fotogramas';

  @override
  String get adminTrickplayWidthResolutionsHint =>
      'Anchos de píxeles separados por comas (p. ej. 320)';

  @override
  String get adminTrickplayQuality => 'Calidad';

  @override
  String get adminTrickplayQScale => 'Escala de calidad';

  @override
  String get adminTrickplayQScaleSubtitle =>
      'Valores más bajos = mejor calidad, archivos más grandes';

  @override
  String get adminTrickplayJpegQuality => 'Calidad JPEG';

  @override
  String get adminTrickplayProcessing => 'Procesamiento';

  @override
  String get adminTasksEmpty => 'No se encontraron tareas programadas';

  @override
  String get adminTasksNoFilterMatch =>
      'Ninguna tarea coincide con el filtro actual';

  @override
  String get adminTaskCancelling => 'Cancelando...';

  @override
  String get adminTaskRunning => 'Ejecutando...';

  @override
  String get adminTaskNeverRun => 'Nunca ejecutada';

  @override
  String get adminTaskStop => 'Detener';

  @override
  String get adminRunningTasks => 'Tareas en ejecución';

  @override
  String get adminTaskRun => 'Ejecutar';

  @override
  String get adminTaskDetailLastExecution => 'Última ejecución';

  @override
  String get adminTaskDetailStarted => 'Iniciada';

  @override
  String get adminTaskDetailEnded => 'Finalizada';

  @override
  String get adminTaskDetailDuration => 'Duración';

  @override
  String get adminTaskDetailErrorLabel => 'Error:';

  @override
  String adminTaskTriggerDaily(String time) {
    return 'Cada día a las $time';
  }

  @override
  String adminTaskTriggerWeekly(String day, String time) {
    return 'Cada $day a las $time';
  }

  @override
  String get adminTaskTriggerStartup => 'Al iniciar la aplicación';

  @override
  String get adminTaskTriggerTypeDaily => 'Diario';

  @override
  String get adminTaskTriggerTypeWeekly => 'Semanal';

  @override
  String get adminTaskTriggerTypeInterval => 'Por intervalo';

  @override
  String get adminTaskTriggerIntervalLabel => 'Intervalo';

  @override
  String get adminTaskTriggerEveryHour => 'Cada hora';

  @override
  String adminTaskTriggerHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count horas',
      one: '1 hora',
    );
    return '$_temp0';
  }

  @override
  String get adminTaskTriggerTime => 'Hora';

  @override
  String get adminActivityJustNow => 'Ahora mismo';

  @override
  String get adminActivityLastHour => 'Última hora';

  @override
  String get adminActivityToday => 'Hoy';

  @override
  String get adminActivityYesterday => 'Ayer';

  @override
  String get adminActivityOlder => 'Anteriores';

  @override
  String adminActivityDaysAgo(int days) {
    return 'hace $days d';
  }

  @override
  String adminActivityHoursAgo(int hours) {
    return 'hace $hours h';
  }

  @override
  String adminActivityMinutesAgo(int minutes) {
    return 'hace $minutes min';
  }

  @override
  String get adminActivityNow => 'ahora';

  @override
  String adminActivityMinutesShort(int minutes) {
    return '$minutes min';
  }

  @override
  String adminActivityHoursShort(int hours) {
    return '$hours h';
  }

  @override
  String adminActivityDaysShort(int days) {
    return '$days d';
  }

  @override
  String adminActivityDateShort(int month, int day) {
    return '$day/$month';
  }

  @override
  String get adminTrickplayDescription =>
      'Configura la generación de imágenes de Trickplay para las miniaturas de vista previa al avanzar o retroceder.';

  @override
  String get adminNetworkingPublicHttpsPort => 'Puerto HTTPS público';

  @override
  String get adminNetworkingBaseUrl => 'URL base';

  @override
  String get adminNetworkingBaseUrlHint => 'p. ej. /jellyfin';

  @override
  String get adminNetworkingPublicHttpPort => 'Puerto HTTP público';

  @override
  String get adminNetworkingRequireHttps => 'Exigir HTTPS';

  @override
  String get adminNetworkingRequireHttpsHint =>
      'Redirigir todas las peticiones remotas a HTTPS. No tiene efecto si el servidor no tiene un certificado válido.';

  @override
  String get adminNetworkingCertPassword => 'Contraseña del certificado';

  @override
  String get adminNetworkingEnableIpv4 => 'Activar IPv4';

  @override
  String get adminNetworkingEnableIpv6 => 'Activar IPv6';

  @override
  String get adminNetworkingLocalSubnets => 'Redes LAN';

  @override
  String get adminNetworkingRemoteIpFilterLabel => 'Filtro de IP remota';

  @override
  String get adminPlaybackVaapiDevice => 'Dispositivo VA-API';

  @override
  String get adminPlaybackAutomatic => '0 = automático';

  @override
  String get adminPlaybackTranscodeTempPath =>
      'Ruta temporal de transcodificación';

  @override
  String get adminPlaybackSegmentDeletion =>
      'Permitir eliminación de segmentos';

  @override
  String get adminPlaybackSegmentKeep => 'Conservar segmentos (segundos)';

  @override
  String get adminPlaybackThrottleBuffering => 'Limitar el búfer';

  @override
  String get adminPlaybackThrottleDelay => 'Retardo de limitación (segundos)';

  @override
  String get adminPlaybackEnableSubtitleExtraction =>
      'Permitir la extracción de subtítulos sobre la marcha';

  @override
  String get adminResumeMinPct => 'Porcentaje mínimo de reanudación';

  @override
  String get adminResumeMinPctSubtitle =>
      'El contenido debe reproducirse más allá de este porcentaje para guardar el progreso';

  @override
  String get adminResumeMaxPct => 'Porcentaje máximo de reanudación';

  @override
  String get adminResumeMaxPctSubtitle =>
      'El contenido se considera reproducido por completo al superar este porcentaje';

  @override
  String get adminResumeMinDuration =>
      'Duración mínima de reanudación (segundos)';

  @override
  String get adminResumeMinDurationSubtitle =>
      'Los elementos más cortos no se pueden reanudar';

  @override
  String get adminTrickplayScanBehavior => 'Comportamiento de escaneo';

  @override
  String get adminTrickplayProcessPriority => 'Prioridad del proceso';

  @override
  String get adminTrickplayTileWidth => 'Ancho del mosaico';

  @override
  String get adminTrickplayTileHeight => 'Alto del mosaico';

  @override
  String get adminTrickplayProcessThreads => 'Hilos de proceso';

  @override
  String get adminTrickplayWidthResolutions => 'Resoluciones de ancho';

  @override
  String get adminMetadataDefault => 'Predeterminado';

  @override
  String get adminMetadataContentTypeUpdated => 'Tipo de contenido actualizado';

  @override
  String adminMetadataContentTypeFailed(String error) {
    return 'No se pudo actualizar el tipo de contenido: $error';
  }

  @override
  String get adminGeneralSlowResponseThreshold =>
      'Umbral de respuesta lenta (ms)';

  @override
  String get adminGeneralEnableSlowResponse =>
      'Activar los avisos de respuesta lenta';

  @override
  String get adminGeneralQuickConnect => 'Activar Quick Connect';

  @override
  String get adminGeneralSectionServer => 'Servidor';

  @override
  String get adminGeneralSectionMetadata => 'Metadatos';

  @override
  String get adminGeneralSectionPaths => 'Rutas';

  @override
  String get adminGeneralSectionPerformance => 'Rendimiento';

  @override
  String get adminGeneralCachePath => 'Ruta de caché';

  @override
  String get adminGeneralMetadataPath => 'Ruta de metadatos';

  @override
  String get adminGeneralServerName => 'Nombre del servidor';

  @override
  String get adminGeneralDisplayLanguage => 'Idioma preferido de la interfaz';

  @override
  String get adminSettingsLoadFailed => 'Error al cargar los ajustes';

  @override
  String adminChannelMappingsUpdateFailed(String error) {
    return 'No se pudieron actualizar las asignaciones: $error';
  }

  @override
  String adminTimeLimitDuration(String duration) {
    return 'Límite de tiempo: $duration';
  }

  @override
  String get folders => 'Carpetas';

  @override
  String get libraries => 'Bibliotecas';

  @override
  String get syncPlay => 'SyncPlay';

  @override
  String get syncPlayDisabledTitle => 'SyncPlay desactivado';

  @override
  String get syncPlayDisabledMessage =>
      'Activa SyncPlay en Ajustes para usar la reproducción sincronizada.';

  @override
  String get syncPlayServerUnsupportedTitle => 'Servidor no compatible';

  @override
  String get syncPlayServerUnsupportedMessage =>
      'SyncPlay requiere un servidor Jellyfin. El servidor actual no lo admite.';

  @override
  String get syncPlayGroupFallbackName => 'Grupo SyncPlay';

  @override
  String get syncPlayGroupTooltip => 'Grupo SyncPlay';

  @override
  String syncPlayParticipantCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# participantes',
      one: '# participante',
    );
    return '$_temp0';
  }

  @override
  String get syncPlayIgnoreWait => 'No esperar';

  @override
  String get syncPlayIgnoreWaitSubtitle =>
      'No hagas esperar al grupo mientras este dispositivo carga';

  @override
  String get syncPlayContinueLocallyNoWait =>
      'Continuar localmente sin esperar a miembros lentos';

  @override
  String get syncPlayRepeat => 'Repetir';

  @override
  String get syncPlayRepeatSubtitle => 'Repite un elemento o toda la cola';

  @override
  String get syncPlayRepeatOne => 'Uno';

  @override
  String get syncPlayShuffleSubtitle =>
      'Reproduce la cola en orden o de forma aleatoria';

  @override
  String get syncPlayShuffleModeShuffled => 'Aleatorio';

  @override
  String get syncPlayShuffleModeSorted => 'Ordenado';

  @override
  String get syncPlayParticipantYou => 'Tú';

  @override
  String syncPlayGroupSubtitle(String participants, String detail) {
    return '$participants · $detail';
  }

  @override
  String get syncPlayNothingQueued => 'aún no hay nada en la cola';

  @override
  String get syncPlayOthersCanJoinHint =>
      'Los demás pueden unirse desde su pantalla de SyncPlay mientras exista este grupo.';

  @override
  String get syncPlaySyncCurrentQueue =>
      'Sincronizar la cola de reproducción actual';

  @override
  String get syncPlaySyncCurrentQueueSubtitle =>
      'Sustituye la cola del grupo por lo que se está reproduciendo en este dispositivo';

  @override
  String get syncPlayLeaveGroup => 'Salir del grupo';

  @override
  String get syncPlayGroupQueue => 'Cola del grupo';

  @override
  String syncPlayQueueItemFallback(int index) {
    return 'Elemento $index';
  }

  @override
  String get syncPlayPlayNow => 'Reproducir ahora';

  @override
  String get syncPlayCreateNewGroup => 'Crear un nuevo grupo';

  @override
  String get syncPlayCreateGroupSubtitle =>
      'Mira algo a la vez con todos los que se unan';

  @override
  String get syncPlayGroupName => 'Nombre del grupo';

  @override
  String get syncPlayDefaultGroupName => 'Mi grupo SyncPlay';

  @override
  String get syncPlayCreateGroup => 'Crear grupo';

  @override
  String get syncPlayAvailableGroups => 'Grupos disponibles';

  @override
  String syncPlayAvailableGroupsCount(int count) {
    return 'Grupos disponibles · $count';
  }

  @override
  String get syncPlayNoGroupsAvailable => 'No hay grupos disponibles';

  @override
  String get syncPlayNoGroupsAvailableHint =>
      'Aquí aparecerán los grupos que creen otras personas en este servidor.';

  @override
  String get syncPlayJoinGroupQuestion => '¿Unirte al grupo SyncPlay?';

  @override
  String get syncPlayJoinGroupWarning =>
      'Si te unes a un grupo SyncPlay, puede que se sustituya tu cola de reproducción actual. ¿Continuar?';

  @override
  String get syncPlayJoinReplacesQueueNote =>
      'Unirte a un grupo puede reemplazar tu cola de reproducción actual.';

  @override
  String get syncPlayJoin => 'Unirse';

  @override
  String get syncPlayStateIdle => 'Inactivo';

  @override
  String get syncPlayStateWaiting => 'Esperando';

  @override
  String get syncPlayStatePaused => 'En pausa';

  @override
  String get syncPlayStatePlaying => 'Reproduciendo';

  @override
  String syncPlayUserJoinedGroup(String userName) {
    return '$userName se ha unido al grupo SyncPlay';
  }

  @override
  String syncPlayUserLeftGroup(String userName) {
    return '$userName ha salido del grupo SyncPlay';
  }

  @override
  String get syncPlayAccessDeniedTitle => 'Acceso a SyncPlay denegado';

  @override
  String get syncPlayAccessDeniedMessage =>
      'No tienes acceso a uno o más elementos de este grupo de SyncPlay. Pide al propietario del grupo que revise los permisos de la biblioteca o que elija otra cola.';

  @override
  String syncPlaySyncingPlaybackToGroup(String groupName) {
    return 'Sincronizando la reproducción con $groupName';
  }

  @override
  String get voiceSearchUnavailable =>
      'La búsqueda por voz no está disponible.';

  @override
  String get dolbyVisionDirectPlayFailedTitle =>
      'Error en la reproducción directa de Dolby Vision';

  @override
  String get dolbyVisionDirectPlayFailedMessage =>
      'No se pudo iniciar la reproducción directa de este flujo Dolby Vision. ¿Volver a intentarlo con la transcodificación del servidor?';

  @override
  String get retryWithTranscode => 'Reintentar con transcodificación';

  @override
  String get dolbyVisionNotSupportedTitle => 'Dolby Vision no es compatible';

  @override
  String get dolbyVisionNotSupportedMessage =>
      'Este dispositivo no puede decodificar contenido Dolby Vision directamente. Usa la alternativa HDR10 o pide al servidor que lo transcodifique.';

  @override
  String get rememberMyChoice => 'Recordar mi elección';

  @override
  String get playHdr10Fallback => 'Reproducir en HDR10';

  @override
  String get requestTranscode => 'Solicitar transcodificación';

  @override
  String integrationRowsDiscoveredCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# filas detectadas',
      one: '# fila detectada',
    );
    return '$_temp0';
  }

  @override
  String get seeAll => 'Ver todo';

  @override
  String get noItems => 'No hay elementos';

  @override
  String get switchUser => 'Cambiar de usuario';

  @override
  String get remoteControl => 'Control remoto';

  @override
  String get mediaBarLoading => 'Cargando la barra multimedia...';

  @override
  String get mediaBarError => 'No se pudo cargar la barra multimedia';

  @override
  String get offlineServerUnavailable =>
      'Conectado a internet, pero el servidor actual no está disponible.';

  @override
  String get offlineNoInternet =>
      'Estás sin conexión. Solo está disponible el contenido descargado.';

  @override
  String get offlineFileNotAvailable => 'Archivo no disponible';

  @override
  String get offlineSwitchServer => 'Cambiar de servidor';

  @override
  String get offlineSavedMedia => 'Descargas';

  @override
  String get offlineBannerTitle => 'Estás sin conexión';

  @override
  String get offlineBannerSubtitle => 'Mostrando tus descargas';

  @override
  String get serverUnreachableBannerTitle =>
      'No se puede conectar con tu servidor';

  @override
  String get serverUnreachableBannerSubtitle =>
      'Reproduciendo desde las descargas hasta que vuelva';

  @override
  String get castGoogleCast => 'Google Cast';

  @override
  String get castAirPlay => 'AirPlay';

  @override
  String get castDlna => 'DLNA';

  @override
  String get castRemotePlayback => 'Reproducción remota';

  @override
  String castControlFailed(String error) {
    return 'Error en el control de transmisión: $error';
  }

  @override
  String castKindControls(String kind) {
    return 'Controles de $kind';
  }

  @override
  String get castDeviceVolume => 'Volumen del dispositivo';

  @override
  String get castVolumeUnavailable => 'No disponible';

  @override
  String castStopKind(String kind) {
    return 'Detener $kind';
  }

  @override
  String get audioLabel => 'Audio';

  @override
  String get subtitlesLabel => 'Subtítulos';

  @override
  String get pinConfirmTitle => 'Confirmar PIN';

  @override
  String get pinSetTitle => 'Establecer PIN';

  @override
  String get pinEnterTitle => 'Introducir PIN';

  @override
  String get pinReenterToConfirm => 'Vuelve a introducir tu PIN para confirmar';

  @override
  String pinEnterNDigit(int length) {
    return 'Introduce un PIN de $length dígitos';
  }

  @override
  String pinEnterYourNDigit(int length) {
    return 'Introduce tu PIN de $length dígitos';
  }

  @override
  String get kidsMode => 'Modo infantil';

  @override
  String get kidsModeSubtitle =>
      'Simplifica la app y bloquea la salida con un PIN';

  @override
  String get kidsModeExit => 'Salir del modo infantil';

  @override
  String get kidsModeExitSubtitle =>
      'Introduce tu PIN para recuperar la app completa';

  @override
  String get pinIncorrect => 'PIN incorrecto';

  @override
  String pinTryAgainIn(String wait) {
    return 'Demasiados intentos. Vuelve a intentarlo en $wait.';
  }

  @override
  String get pinMismatch => 'Los PIN no coinciden';

  @override
  String get pinForgot => '¿Olvidaste el PIN?';

  @override
  String get pinClear => 'Borrar';

  @override
  String get pinBackspace => 'Retroceso';

  @override
  String get quickConnectAuthorized => 'Solicitud de Quick Connect autorizada.';

  @override
  String get quickConnectInvalidOrExpired =>
      'El código de Quick Connect no es válido o ha caducado.';

  @override
  String get quickConnectNotSupported =>
      'Quick Connect no es compatible con este servidor.';

  @override
  String get quickConnectAuthorizeFailed =>
      'Error al autorizar el código de Quick Connect.';

  @override
  String get quickConnectDisabled =>
      'Quick Connect está desactivado en este servidor.';

  @override
  String get quickConnectForbidden =>
      'Tu cuenta no puede autorizar esta solicitud de Quick Connect.';

  @override
  String get quickConnectNotFound =>
      'No se encontró el código de Quick Connect. Prueba con un nuevo código.';

  @override
  String quickConnectFailedWithMessage(String message) {
    return 'Error de Quick Connect: $message';
  }

  @override
  String get quickConnectEnterCode => 'Introducir código';

  @override
  String get quickConnectAuthorize => 'Autorizar';

  @override
  String remoteCommandFailed(String error) {
    return 'Error en el comando: $error';
  }

  @override
  String get remoteControlTitle => 'Control remoto';

  @override
  String get remoteFailedToLoadSessions => 'Error al cargar las sesiones';

  @override
  String get remoteNoSessions => 'No hay sesiones controlables';

  @override
  String get remoteStartPlayback => 'Iniciar reproducción en otro dispositivo';

  @override
  String get unknownUser => 'Desconocido';

  @override
  String get unknownItem => 'Desconocido';

  @override
  String get remoteNothingPlaying =>
      'No se está reproduciendo nada en esta sesión';

  @override
  String get castingStarted =>
      'Transmisión iniciada en el dispositivo seleccionado';

  @override
  String castingFailed(String error) {
    return 'No se pudo iniciar la transmisión: $error';
  }

  @override
  String get noRemoteDevices =>
      'No hay dispositivos de reproducción remota disponibles.';

  @override
  String get noRemoteDevicesIos =>
      'No hay dispositivos de reproducción remota disponibles.\n\nEn iOS, es posible que los destinos AirPlay no estén disponibles en el simulador.';

  @override
  String get trackActionPlayNext => 'Reproducir a continuación';

  @override
  String get trackActionViewDetails => 'Ver detalles';

  @override
  String get trackActionAddToQueue => 'Añadir a la cola';

  @override
  String get trackActionAddToPlaylist => 'Añadir a lista de reproducción';

  @override
  String get trackActionCancelDownload => 'Cancelar descarga';

  @override
  String get trackActionDeleteFromPlaylist =>
      'Eliminar de la lista de reproducción';

  @override
  String get trackActionMoveUp => 'Mover arriba';

  @override
  String get trackActionMoveDown => 'Mover abajo';

  @override
  String get trackActionRemoveFromFavorites => 'Quitar de favoritos';

  @override
  String get trackActionAddToFavorites => 'Añadir a favoritos';

  @override
  String get trackActionGoToAlbum => 'Ir al álbum';

  @override
  String get trackActionGoToArtist => 'Ir al artista';

  @override
  String trackActionDownloading(String name) {
    return 'Descargando $name...';
  }

  @override
  String get trackActionDeletedFile => 'Archivo descargado eliminado';

  @override
  String get trackActionDeleteFileFailed =>
      'No se pudo eliminar el archivo descargado';

  @override
  String get shuffleBy => 'Aleatorio por';

  @override
  String get shuffleSelectLibrary => 'Seleccionar biblioteca';

  @override
  String get shuffleSelectGenre => 'Seleccionar género';

  @override
  String get shuffleLibrary => 'Biblioteca';

  @override
  String get shuffleGenre => 'Género';

  @override
  String get shuffleNoLibraries =>
      'No hay bibliotecas compatibles disponibles.';

  @override
  String get shuffleNoGenres =>
      'No se encontraron géneros para este modo aleatorio.';

  @override
  String get posterDisplayTitle => 'Visualización';

  @override
  String get posterImageType => 'Tipo de imagen';

  @override
  String get imageTypePoster => 'Póster';

  @override
  String get imageTypeThumbnail => 'Miniatura';

  @override
  String get imageTypeBanner => 'Banner';

  @override
  String get playlistAddFailed => 'Error al añadir a la lista de reproducción';

  @override
  String get playlistCreateFailed => 'Error al crear la lista de reproducción';

  @override
  String get playlistNew => 'Nueva lista de reproducción';

  @override
  String get playlistCreate => 'Crear';

  @override
  String get playlistCreateNew => 'Crear nueva lista de reproducción';

  @override
  String get playlistNoneFound => 'No se encontraron listas de reproducción';

  @override
  String get addToPlaylist => 'Añadir a lista de reproducción';

  @override
  String get removeFromPlaylist => 'Quitar de la lista de reproducción';

  @override
  String removeFromPlaylistConfirm(String item, String playlist) {
    return '¿Quitar $item de $playlist?';
  }

  @override
  String get removeFromPlaylistFailed =>
      'No se pudo quitar de la lista de reproducción';

  @override
  String get lyricsNotAvailable => 'No hay letra disponible';

  @override
  String get upNext => 'A continuación';

  @override
  String get playNext => 'Reproducir a continuación';

  @override
  String get stillWatchingContent =>
      'La reproducción se ha pausado. ¿Sigues viendo?';

  @override
  String get stillWatchingStop => 'Detener';

  @override
  String get stillWatchingContinue => 'Continuar';

  @override
  String skipSegment(String segment) {
    return 'Saltar $segment';
  }

  @override
  String get liveTv => 'TV en directo';

  @override
  String get continueWatchingAndNextUp => 'Continuar viendo y A continuación';

  @override
  String downloadingBatchProgress(int current, int total, String fileName) {
    return 'Descargando $current/$total — $fileName';
  }

  @override
  String downloadingFile(String fileName) {
    return 'Descargando $fileName';
  }

  @override
  String get nextEpisode => 'Siguiente episodio';

  @override
  String get moreFromThisSeason => 'Más de esta temporada';

  @override
  String get playerTooltipPlaybackSpeed => 'Velocidad de reproducción';

  @override
  String get playerTooltipCastControls => 'Controles de transmisión';

  @override
  String get playerTooltipPlaybackQuality => 'Tasa de bits';

  @override
  String get playerTooltipEnterFullscreen => 'Entrar en pantalla completa';

  @override
  String get playerTooltipExitFullscreen => 'Salir de pantalla completa';

  @override
  String get playerTooltipFloatOnTop => 'Mantener por encima';

  @override
  String get playerTooltipExitFloatOnTop => 'Dejar de mantener por encima';

  @override
  String get playerTooltipLockLandscape => 'Bloquear en horizontal';

  @override
  String get playerTooltipUnlockOrientation => 'Permitir rotación';

  @override
  String get playerTooltipPrevious => 'Anterior';

  @override
  String get playerTooltipSeekBack => 'Retroceder';

  @override
  String get playerTooltipSeekForward => 'Avanzar';

  @override
  String get playerTooltipMinimize => 'Minimizar reproductor';

  @override
  String get miniPlayerOpenPlayer => 'Abrir reproductor';

  @override
  String get contextMenuMarkWatched => 'Marcar como visto';

  @override
  String get contextMenuMarkUnwatched => 'Marcar como no visto';

  @override
  String get contextMenuAddToFavorites => 'Añadir a favoritos';

  @override
  String get contextMenuRemoveFromFavorites => 'Quitar de favoritos';

  @override
  String get contextMenuGoToSeries => 'Ir a la serie';

  @override
  String get contextMenuHideFromContinueWatching =>
      'Ocultar de Continuar viendo';

  @override
  String get contextMenuHideFromNextUp => 'Ocultar de A continuación';

  @override
  String get contextMenuAddToCollection => 'Añadir a una colección';

  @override
  String get contextMenuRemoveFromCollection => 'Quitar de la colección';

  @override
  String removeFromCollectionConfirm(String item, String collection) {
    return '¿Quitar $item de $collection? Seguirá en tu biblioteca.';
  }

  @override
  String get removeFromCollectionFailed => 'No se pudo quitar de la colección';

  @override
  String get settingsAdministrationSubtitle =>
      'Accede al panel de administración del servidor';

  @override
  String get settingsDynamicContent => 'Contenido dinámico';

  @override
  String get settingsDynamicContentSubtitle =>
      'Barra multimedia y superposiciones visuales';

  @override
  String get settingsAboutSubtitle =>
      'Versión de la aplicación, información legal y créditos';

  @override
  String get settingsSortServersBy => 'Ordenar servidores por';

  @override
  String get settingsLastUsed => 'Último uso';

  @override
  String get settingsAlphabetical => 'Alfabético';

  @override
  String get settingsAllowSelfSignedCerts =>
      'Permitir certificados autofirmados';

  @override
  String get settingsAllowSelfSignedCertsSubtitle =>
      'Confiar en servidores que usan certificados TLS autofirmados o de una CA privada. Actívalo solo para servidores que controles. Esto desactiva la validación de certificados en todas las conexiones.';

  @override
  String get untrustedServerCertificate =>
      'El certificado de este servidor no es de confianza. Si es tu propio servidor y usa un certificado autofirmado o privado, puedes permitirlo aquí.';

  @override
  String get clientCertTitle => 'Certificado de cliente';

  @override
  String clientCertHost(String host) {
    return 'Certificado para $host';
  }

  @override
  String get clientCertChooseFile => 'Elegir archivo';

  @override
  String get clientCertPassword => 'Contraseña del certificado';

  @override
  String get clientCertStartUpload => 'Enviar desde el móvil';

  @override
  String get clientCertUploadHint =>
      'Escanea este código con tu móvil o abre la dirección en su navegador; después elige el archivo y escribe su contraseña.';

  @override
  String get clientCertStopUpload => 'Dejar de esperar';

  @override
  String get clientCertNoFileData =>
      'No se pudo leer el archivo. Inténtalo de nuevo.';

  @override
  String get clientCertPickFailed =>
      'No se pudo abrir el selector de archivos.';

  @override
  String get clientCertUploadFailed =>
      'No se pudo abrir la página de envío. Inténtalo de nuevo.';

  @override
  String get clientCertNoSecureStorage =>
      'Este dispositivo no tiene almacenamiento seguro, así que no se puede guardar el certificado. En Linux, instala libsecret y vuelve a intentarlo.';

  @override
  String get clientCertDecodeFailed =>
      'Ese archivo no se puede leer como certificado. Asegúrate de que sea .p12 o .pfx.';

  @override
  String get clientCertWrongPassword =>
      'Esa contraseña no desbloquea este certificado.';

  @override
  String get clientCertRequired =>
      'Este servidor necesita un certificado de cliente (mTLS). Añade uno para este host para continuar.';

  @override
  String clientCertExpired(String date) {
    return 'El certificado de este servidor caducó el $date. Sustitúyelo para continuar.';
  }

  @override
  String get clientCertAddButton => 'Añadir certificado de cliente';

  @override
  String get settingsClientCertificates => 'Certificados de cliente';

  @override
  String get settingsClientCertificatesSubtitle =>
      'Certificados que esta app presenta a los servidores que los piden (mTLS)';

  @override
  String get clientCertSubject => 'Sujeto';

  @override
  String clientCertExpires(String date) {
    return 'Caduca el $date';
  }

  @override
  String get clientCertReplace => 'Sustituir';

  @override
  String get clientCertAdd => 'Añadir certificado';

  @override
  String get clientCertAddHostPrompt =>
      '¿Qué host del servidor necesita un certificado?';

  @override
  String get itemBlockedByParentalControls => 'Esto no está disponible';

  @override
  String get blockedRatingsCeilingHint =>
      'Bloquear una clasificación también bloquea todas las superiores.';

  @override
  String get blockedRatingsUnrankedSection => 'Solo se bloquean a sí mismas';

  @override
  String get settingsHomePage => 'Página de inicio';

  @override
  String get settingsTwentyFourHourClock => 'Reloj de 24 horas';

  @override
  String get settingsTwentyFourHourClockSubtitle =>
      'Usa el formato de 24 horas en todos los sitios donde se muestra el reloj';

  @override
  String get settingsDateFormat => 'Formato de fecha';

  @override
  String get settingsDateFormatDescription =>
      'Elige entre mes-día, día-mes o el formato regional para las fechas del calendario y de estreno';

  @override
  String get dateFormatSystem => 'Formato regional';

  @override
  String get dateFormatMonthDay => 'Mes / día (nov 10)';

  @override
  String get dateFormatDayMonth => 'Día / mes (10 nov)';

  @override
  String get settingsShowShuffleButtonInNavigation =>
      'Mostrar el botón de reproducción aleatoria en la barra de navegación';

  @override
  String get settingsShowGenresButtonInNavigation =>
      'Mostrar el botón de géneros en la barra de navegación';

  @override
  String get settingsShowFavoritesButtonInNavigation =>
      'Mostrar el botón de favoritos en la barra de navegación';

  @override
  String get settingsShowLiveTvButtonInNavigation =>
      'Mostrar el botón de TV en directo en la barra de navegación cuando el servidor tenga una biblioteca de TV en directo';

  @override
  String get settingsShowLibrariesButtonInNavigation =>
      'Mostrar el botón de bibliotecas en la barra de navegación';

  @override
  String get settingsAlwaysExpandNavbarLabels =>
      'Mostrar siempre las etiquetas de texto en la barra de navegación superior';

  @override
  String get settingsLibraryVisibilitySubtitle =>
      'Muestra u oculta cada biblioteca en la página de inicio. Reinicia kOS TV para aplicar los cambios.';

  @override
  String get settingsMediaBarAndLocalPreviews =>
      'Barra multimedia y vistas previas locales';

  @override
  String get settingsVisualOverlays => 'Superposiciones visuales';

  @override
  String get settingsSeasonalSurprise => 'Sorpresa de temporada';

  @override
  String get useNativeEmulator => 'Emulación nativa';

  @override
  String get useNativeEmulatorSubtitle =>
      'Juega con núcleos nativos en lugar del reproductor web EmulatorJS';

  @override
  String get emulatorCores => 'Núcleos del emulador';

  @override
  String get emulatorCoresSubtitle =>
      'Descarga sistemas para jugar de forma nativa';

  @override
  String get emulatorCoresDescription =>
      'Elige qué sistemas instalar. Los núcleos los proporciona el proyecto libretro y permiten que los juegos funcionen de forma nativa en lugar de en una vista de navegador.';

  @override
  String get emulatorCoreDownloading => 'Descargando';

  @override
  String get emulatorCoreUnavailable => 'No disponible para este dispositivo';

  @override
  String get emulatorCoreDownloadFailed =>
      'No se pudo descargar el núcleo. Comprueba tu conexión y vuelve a intentarlo.';

  @override
  String emulatorCoreResetSettings(String system) {
    return 'Restablecer los ajustes de $system';
  }

  @override
  String get emulatorCoreSettingsReset => 'Ajustes restablecidos.';

  @override
  String get emulatorCoreResetSettingsFailed =>
      'No se pudieron restablecer los ajustes. Comprueba tu conexión y vuelve a intentarlo.';

  @override
  String get downloadedGames => 'Juegos descargados';

  @override
  String get downloadedGamesSubtitle =>
      'Libera el espacio que ocupan los archivos de juegos';

  @override
  String get downloadedGamesDescription =>
      'Los juegos se copian en este dispositivo antes de jugarlos. Quita los que ya hayas terminado para liberar espacio. Las partidas guardadas se quedan en el servidor y no se borran.';

  @override
  String get downloadedGamesEmpty =>
      'Aún no se ha descargado ningún juego en este dispositivo.';

  @override
  String downloadedGamesTotal(int count, String size) {
    return '$count juegos, $size';
  }

  @override
  String get removeAllDownloadedGames => 'Quitar todos';

  @override
  String removeDownloadedGameConfirm(String title) {
    return '¿Quitar $title de este dispositivo? Se volverá a descargar la próxima vez que juegues.';
  }

  @override
  String get removeAllDownloadedGamesConfirm =>
      '¿Quitar todos los juegos descargados de este dispositivo? Se volverán a descargar la próxima vez que juegues a ellos.';

  @override
  String get settingsHigh => 'Alto';

  @override
  String get settingsLow => 'Bajo';

  @override
  String get settingsCustomPath => 'Ruta personalizada';

  @override
  String get settingsEnterDownloadFolderPath =>
      'Introduce la ruta de la carpeta de descargas';

  @override
  String get settingsConcurrentDownloads => 'Descargas simultáneas';

  @override
  String get settingsConcurrentDownloadsDescription =>
      'Número máximo de elementos que se descargan a la vez.';

  @override
  String get settingsAppInfo => 'INFORMACIÓN DE LA APLICACIÓN';

  @override
  String get settingsLegal => 'LEGAL';

  @override
  String get settingsLicenses => 'Licencias';

  @override
  String get settingsOpenSourceLicenseNotices =>
      'Avisos de licencia de código abierto';

  @override
  String get settingsPrivacyPolicy => 'Política de privacidad';

  @override
  String get settingsPrivacyPolicySubtitle => 'Cómo trata kOS TV tus datos';

  @override
  String get settingsCheckForUpdates => 'Buscar actualizaciones';

  @override
  String get settingsCheckForUpdatesSubtitle =>
      'Busca la última versión de kOS TV';

  @override
  String get settingsBoth => 'Ambos';

  @override
  String get settingsShuffleContentTypeFilter =>
      'Filtro de tipo de contenido para el modo aleatorio';

  @override
  String get settingsAudioPreferencesSubtitle =>
      'Pistas de audio, procesamiento y opciones de passthrough';

  @override
  String get settingsAutomationAndQueueSubtitle =>
      'Reproducción y secuenciación automatizadas';

  @override
  String get settingsSyncplaySubtitle =>
      'Ver contenido con amigos de este servidor, todos a la vez';

  @override
  String get settingsSkipIntrosAndOutros => '¿Saltar la intro y los créditos?';

  @override
  String settingsMediaSegmentTypeAction(String segment) {
    return 'Segmentos de $segment';
  }

  @override
  String get settingsMediaSegmentCountdown =>
      'Cuenta atrás de los segmentos multimedia';

  @override
  String get settingsProgressBar => 'Barra de progreso';

  @override
  String get settingsTimer => 'Temporizador';

  @override
  String get settingsNone => 'Ninguno';

  @override
  String get settingsSkipButtonAutoHide =>
      'Ocultar automáticamente el botón de saltar';

  @override
  String get settingsSkipButtonAutoHideDescription =>
      'Oculta el botón para saltar la intro y los créditos tras unos segundos.';

  @override
  String get settingsPromptUser => 'Preguntar al usuario';

  @override
  String get settingsSkip => 'Saltar';

  @override
  String get settingsDoNothing => 'No hacer nada';

  @override
  String get settingsMaxBitrateDescription =>
      'Limita la tasa de bits de transmisión. El contenido que supere este umbral se transcodificará para ajustarse.';

  @override
  String get settingsMaxResolutionDescription =>
      'Limita la resolución máxima que pedirá el reproductor. El contenido de mayor resolución se transcodificará a una inferior.';

  @override
  String get settingsPlayerZoomDescription =>
      'Cómo se escala el vídeo en la pantalla. Al ampliar para llenar, la imagen se agranda hasta ocupar toda la pantalla y se recortan los bordes. No detecta las bandas negras.';

  @override
  String get settingsPlaybackEngineAndroidTv =>
      'Motor de reproducción (Android TV)';

  @override
  String get settingsPlaybackEngineAndroidTvDescription =>
      'Elige el motor de reproducción predeterminado en los dispositivos Android TV. Los cambios se aplican a partir de la siguiente reproducción.';

  @override
  String get settingsPlaybackEngineMedia3Recommended => 'Media3 (recomendado)';

  @override
  String get settingsPlaybackEngineMpvLegacy => 'mpv (antiguo)';

  @override
  String get settingsRedetectDisplay => 'Volver a detectar la pantalla';

  @override
  String get settingsRedetectDisplayDescription =>
      'Vuelve a preguntar a la tele qué formatos HDR admite. Úsalo si los títulos en Dolby Vision o HDR10 se transcodifican porque la tele o el receptor se encendieron tarde.';

  @override
  String get settingsDisplayIsSdr => 'Mi tele no es HDR';

  @override
  String get settingsDisplayIsSdrDescription =>
      'Deja de anunciar compatibilidad con HDR en esta pantalla. Úsalo solo si la detección sigue indicando un HDR que tu tele no puede mostrar en realidad.';

  @override
  String settingsDisplayRedetected(String formats) {
    return 'Pantalla detectada de nuevo: $formats';
  }

  @override
  String get settingsDisplayNoHdrDetected =>
      'No se ha detectado ningún formato HDR';

  @override
  String get settingsDisplayMarkedSdr => 'Pantalla guardada como SDR';

  @override
  String get settingsDolbyVisionFallback => 'Alternativa a Dolby Vision';

  @override
  String get settingsDolbyVisionFallbackDescription =>
      'Qué hacer con los títulos Dolby Vision en dispositivos que no pueden decodificar Dolby Vision.';

  @override
  String get settingsAskEachTime => 'Preguntar cada vez';

  @override
  String get settingsPreferHdr10Fallback => 'Preferir la alternativa HDR10';

  @override
  String get settingsPreferServerTranscode =>
      'Preferir la transcodificación del servidor';

  @override
  String get settingsDolbyVisionProfile7DirectPlay =>
      'Reproducción directa de Dolby Vision perfil 7';

  @override
  String get settingsDolbyVisionProfile7DirectPlayDescription =>
      'Controla si los flujos de Dolby Vision perfil 7 con capa de mejora deben reproducirse directamente.';

  @override
  String get settingsAutoAftkrtEnabled => 'Automático';

  @override
  String get settingsEnabledOnThisDevice => 'Activado';

  @override
  String get settingsDisabledPreferTranscode => 'Desactivado';

  @override
  String get settingsResumeRewindDescription =>
      'Al reanudar la reproducción (desde Continuar viendo o desde la página de un elemento), ¿cuántos segundos debe retroceder?';

  @override
  String get settingsUnpauseRewindDescription =>
      'Al reanudar la reproducción tras pulsar el botón de pausa, ¿cuántos segundos debe retroceder?';

  @override
  String get settingsSkipBackLengthDescription =>
      'Cuántos segundos retroceder al pulsar el botón de retroceso.';

  @override
  String get settingsOneSecond => '1 segundo';

  @override
  String get settingsThreeSeconds => '3 segundos';

  @override
  String get settingsFortyFiveSeconds => '45 segundos';

  @override
  String get settingsSixtySeconds => '60 segundos';

  @override
  String get settingsSkipForwardLengthDescription =>
      'Cuántos segundos avanzar al pulsar el botón de avance rápido.';

  @override
  String get settingsHideControlsAfter => 'Ocultar controles tras';

  @override
  String get settingsHideControlsAfterDescription =>
      'Cuánto tiempo siguen en pantalla los controles del reproductor después de tu última pulsación, toque o movimiento del ratón.';

  @override
  String get settingsHdrControlsDimming => 'Atenuar controles en HDR';

  @override
  String get settingsHdrControlsDimmingDescription =>
      'El blanco se ve mucho más brillante junto a un vídeo HDR, así que los controles del reproductor se atenúan en esta medida mientras se reproduce.';

  @override
  String get settingsBitstreamAc3ToExternalDecoder =>
      'Enviar AC3 en bitstream al decodificador externo';

  @override
  String get settingsCinemaMode => 'Modo cine';

  @override
  String get settingsCinemaModeSubtitle =>
      'Reproducir tráileres y vídeos de introducción antes de la película principal';

  @override
  String get settingsCinemaModeEpisodes => 'Modo cine en episodios';

  @override
  String get settingsCinemaModeEpisodesSubtitle =>
      'Reproduce también prerolls antes de los episodios de series';

  @override
  String get settingsNextUpDisplayDescription =>
      'Extendido muestra una tarjeta completa con la imagen y la descripción del episodio. Mínimo muestra una cuenta atrás compacta superpuesta. Desactivado oculta el aviso por completo.';

  @override
  String get settingsShort => 'Corto';

  @override
  String get settingsLong => 'Largo';

  @override
  String get settingsVeryLong => 'Muy largo';

  @override
  String get settingsVideoStartDelay => 'Retraso de inicio de vídeo';

  @override
  String settingsMillisecondsValue(int value) {
    return '$value ms';
  }

  @override
  String get settingsLiveTvDirect => 'Reproducción directa de TV en directo';

  @override
  String get settingsLiveTvDirectSubtitle =>
      'Activar la reproducción directa en TV en directo';

  @override
  String get settingsOpenGroups => 'Salas de Ver juntos';

  @override
  String get settingsOpenGroupsSubtitle =>
      'Crea una o únete a una que ya esté en marcha';

  @override
  String get settingsSyncplayEnabled => 'Ver juntos';

  @override
  String get settingsSyncplayEnabledSubtitle =>
      'Ver contenido con amigos de este servidor, todos a la vez';

  @override
  String get settingsSyncplayButton => 'Botón de Ver juntos';

  @override
  String get settingsSyncplayButtonSubtitle =>
      'Mostrar el botón de Ver juntos en la barra de navegación';

  @override
  String get settingsSyncplayAdvancedCorrection => 'Corrección avanzada';

  @override
  String get settingsSyncplayAdvancedCorrectionSubtitle =>
      'Retrasos y desfase adicional';

  @override
  String get settingsSyncplaySyncCorrection => 'Corrección de sincronización';

  @override
  String get settingsSyncplaySyncCorrectionSubtitle =>
      'Mantener este dispositivo sincronizado con la sala';

  @override
  String get settingsSyncplaySpeedToSync => 'Velocidad de sincronización';

  @override
  String get settingsSyncplaySpeedToSyncSubtitle =>
      'Reproducir un poco más rápido o más despacio para ponerse al día';

  @override
  String get settingsSyncplaySkipToSync => 'Saltar para sincronizar';

  @override
  String get settingsSyncplaySkipToSyncSubtitle =>
      'Saltar hacia delante cuando haya demasiado desfase';

  @override
  String get settingsSyncplayMinimumSpeedDelay => 'Retraso mínimo de velocidad';

  @override
  String get settingsSyncplayMaximumSpeedDelay => 'Retraso máximo de velocidad';

  @override
  String get settingsSyncplaySpeedDuration => 'Duración de la velocidad';

  @override
  String get settingsSyncplayMinimumSkipDelay => 'Retraso mínimo de salto';

  @override
  String get settingsSyncplayExtraOffset => 'Desfase adicional de SyncPlay';

  @override
  String get onNow => 'En emisión ahora';

  @override
  String get collections => 'Colecciones';

  @override
  String get lastPlayed => 'Última reproducción';

  @override
  String libraryNameWithServer(String libraryName, String serverName) {
    return '$libraryName en $serverName';
  }

  @override
  String latestLibraryName(String libraryName) {
    return 'Añadido recientemente en $libraryName';
  }

  @override
  String recentlyReleasedLibraryName(String libraryName) {
    return 'Lanzamientos recientes de $libraryName';
  }

  @override
  String get autoplayNextEpisode =>
      'Reproducción automática del siguiente episodio';

  @override
  String get autoplayNextEpisodeSubtitle =>
      'Reproduce automáticamente el siguiente episodio cuando esté disponible.';

  @override
  String get skipSilenceTitle => 'Saltar silencios';

  @override
  String get skipSilenceSubtitle =>
      'Salta automáticamente los fragmentos de audio en silencio cuando el flujo lo permite.';

  @override
  String get allowExternalAudioEffectsTitle =>
      'Permitir efectos de audio externos';

  @override
  String get allowExternalAudioEffectsSubtitle =>
      'Permite que las aplicaciones de ecualizador y efectos (p. ej., Wavelet) se conecten a las sesiones de reproducción de Media3.';

  @override
  String get disableTunnelingTitle => 'Desactivar la tunelización';

  @override
  String get disableTunnelingSubtitle =>
      'Forzar la reproducción sin tunelización. Útil en dispositivos en los que la tunelización provoca cortes de audio o vídeo.';

  @override
  String get enableTunnelingTitle => 'Activar la tunelización';

  @override
  String get enableTunnelingSubtitle =>
      'Avanzado. Enruta el audio y el vídeo por una ruta de hardware acoplada. Desactivado por defecto porque provoca cortes de audio/vídeo en algunos dispositivos.';

  @override
  String get mapDolbyVisionP7Title =>
      'Reproducir siempre Dolby Vision perfil 7 como HDR10';

  @override
  String get mapDolbyVisionP7Subtitle =>
      'Omite la conversión a perfil 8 y convierte los flujos de Dolby Vision perfil 7 en HEVC compatible con HDR10. Úsalo si los flujos convertidos se ven mal.';

  @override
  String get stripDolbyVisionHdr10PlusTitle =>
      'Reproducir Dolby Vision con HDR10+ como HDR10+';

  @override
  String get stripDolbyVisionHdr10PlusSubtitle =>
      'Quita la capa Dolby Vision de los vídeos que también tienen HDR10+. Actívalo si esos vídeos se reproducen con sonido pero con la pantalla en negro.';

  @override
  String get subtitlesUseEmbeddedStyles =>
      'Usar los estilos de subtítulos incrustados';

  @override
  String get subtitlesUseEmbeddedStylesSubtitle =>
      'Aplica los colores, fuentes y posiciones incrustados en la pista de subtítulos. Desactívalo para usar tus preferencias de estilo de subtítulos.';

  @override
  String get subtitlesUseEmbeddedFontSizes =>
      'Usar los tamaños de fuente de subtítulos incrustados';

  @override
  String get subtitlesUseEmbeddedFontSizesSubtitle =>
      'Aplica las indicaciones de tamaño de fuente incrustadas en la pista de subtítulos. Desactívalo para usar el tamaño de subtítulos de tus preferencias de estilo.';

  @override
  String get showMediaDetailsOnLibraryPage => 'Mostrar detalles del contenido';

  @override
  String get showMediaDetailsOnLibraryPageDescription =>
      'Mostrar los detalles del elemento seleccionado en la parte superior de las páginas de biblioteca.';

  @override
  String get libraryCardTitles => 'Títulos bajo los pósteres';

  @override
  String get libraryCardTitlesDescription =>
      'Muestra el título y los detalles de cada elemento bajo su imagen en las cuadrículas de la biblioteca.';

  @override
  String get useDetailedSubHeadings => 'Usar subencabezados detallados';

  @override
  String get useDetailedSubHeadingsDescription =>
      'Muestra una subfila detallada o mínima en las páginas de biblioteca.';

  @override
  String get savedThemesDeleteDialogTitle => '¿Eliminar tema guardado?';

  @override
  String savedThemesDeleteDialogMessage(String themeName) {
    return '¿Eliminar \"$themeName\" de la caché de este dispositivo?';
  }

  @override
  String get themeStore => 'Tienda de temas';

  @override
  String get themeStoreSubtitle => 'Explora y guarda temas de la comunidad';

  @override
  String get themeStoreDescription =>
      'Guarda un tema para usarlo como el resto de tus temas guardados.';

  @override
  String get themeStoreEmpty => 'No hay temas disponibles en este momento.';

  @override
  String get themeStoreLoadFailed =>
      'No se pudo cargar la Tienda de temas. Comprueba tu conexión e inténtalo de nuevo.';

  @override
  String get themeStoreSave => 'Guardar';

  @override
  String get themeStoreSaveAndApply => 'Guardar y aplicar';

  @override
  String get themeStoreSaved => 'Guardado';

  @override
  String get themeStoreInvalidMessage => 'No se pudo cargar este tema.';

  @override
  String themeStoreSavedMessage(String themeName) {
    return 'Se ha guardado \"$themeName\".';
  }

  @override
  String savedThemesDeletedMessage(String themeName) {
    return 'Se ha eliminado \"$themeName\" de este dispositivo.';
  }

  @override
  String savedThemesDeleteFailedMessage(String themeName) {
    return 'No se pudo eliminar \"$themeName\".';
  }

  @override
  String get savedThemesTitle => 'Temas guardados';

  @override
  String get savedThemesDescription =>
      'Estos son temas descargados del complemento del servidor actual. Al eliminarlos solo se borra esta copia local.';

  @override
  String get savedThemesEmpty =>
      'No se encontraron temas guardados para este servidor.';

  @override
  String savedThemesCurrentThemeId(String themeId) {
    return '$themeId • Actualmente activo';
  }

  @override
  String get savedThemesDeleteTooltip => 'Eliminar tema guardado';

  @override
  String get savedThemesManageSubtitle =>
      'Administrar temas de complementos descargados en este dispositivo';

  @override
  String get themeEditor => 'Editor de temas';

  @override
  String get themeEditorSubtitle => 'Abre el editor de temas en tu navegador';

  @override
  String get homeScreen => 'Pantalla de inicio';

  @override
  String get bottomBar => 'Barra inferior';

  @override
  String get homeRowsStyleClassic => 'Clásico';

  @override
  String get homeRowsStyleModern => 'Moderno';

  @override
  String get homeRowsSection => 'Filas de inicio';

  @override
  String get rowsType => 'Tipo de filas';

  @override
  String get rowsTypeDescription =>
      'Clásico mantiene el tipo de imagen y la información superpuesta de cada fila. Moderno usa filas que pasan de póster vertical a imagen de fondo.';

  @override
  String get modernCardsOnMyMediaRow =>
      'Tarjetas modernas en la fila Mi contenido';

  @override
  String get modernCardsOnMyMediaRowDescription =>
      'Muestra pósteres personalizables que se amplían al seleccionarlos. Desactívalo para mostrar siempre la miniatura horizontal.';

  @override
  String get sortOrder => 'Orden';

  @override
  String get ascending => 'Ascendente';

  @override
  String get descending => 'Descendente';

  @override
  String get displayFavoritesRows => 'Mostrar filas de favoritos';

  @override
  String get displayFavoritesRowsSubtitle =>
      'Muestra las filas de películas y series favoritas y otras filas de favoritos en las secciones de Inicio.';

  @override
  String get favoritesRowSorting => 'Orden de las filas de favoritos';

  @override
  String get favoritesRowSortingDescription =>
      'Ordena las filas de favoritos por fecha de adición, fecha de estreno, alfabéticamente y más.';

  @override
  String get favoritesRowSortOrderDescription =>
      'Ordena las filas de favoritos de forma ascendente o descendente.';

  @override
  String get displayCollectionsRows => 'Mostrar filas de colecciones';

  @override
  String get displayCollectionsRowsSubtitle =>
      'Mostrar las filas de colecciones en las secciones de Inicio.';

  @override
  String get collectionsRowSorting => 'Orden de las filas de colecciones';

  @override
  String get collectionsRowSortingDescription =>
      'Ordena las filas de colecciones por fecha de adición, fecha de estreno, alfabéticamente y más.';

  @override
  String get collectionsRowSortOrderDescription =>
      'Ordena las filas de colecciones de forma ascendente o descendente.';

  @override
  String get collectionsRowShowEpisodes => 'Mostrar episodios sueltos';

  @override
  String get collectionsRowShowEpisodesSubtitle =>
      'Despliega las series para mostrar cada episodio por separado.';

  @override
  String get displayGenresRows => 'Mostrar filas de géneros';

  @override
  String get displayGenresRowsSubtitle =>
      'Mostrar las filas de géneros en las secciones de Inicio.';

  @override
  String get genresRowSorting => 'Orden de las filas de géneros';

  @override
  String get genresRowSortingDescription =>
      'Ordena las filas de géneros por fecha de adición, fecha de estreno, alfabéticamente y más.';

  @override
  String get genresRowSortOrderDescription =>
      'Ordena las filas de géneros de forma ascendente o descendente.';

  @override
  String get genresRowItems => 'Elementos de fila de géneros';

  @override
  String get genresRowItemsDescription =>
      'Muestra películas, series o ambas en las filas de géneros.';

  @override
  String get displayStudiosRows => 'Mostrar fila de estudios';

  @override
  String get displayStudiosRowsSubtitle =>
      'Muestra la fila de estudios en las secciones de Inicio.';

  @override
  String get sinceYouWatched => 'Porque has visto';

  @override
  String get sinceYouWatchedRowTitle => 'Porque has visto';

  @override
  String sinceYouWatchedItemRowTitle(String title) {
    return 'Porque has visto «$title»';
  }

  @override
  String sinceYouWatchedRowNumber(int number) {
    return 'Fila «Porque has visto» $number';
  }

  @override
  String get displaySinceYouWatchedRows => 'Mostrar filas «Porque has visto»';

  @override
  String get displaySinceYouWatchedRowsSubtitle =>
      'Muestra y personaliza las filas «Porque has visto» en las secciones de Inicio.';

  @override
  String get sinceYouWatchedSource => 'Fuente de recomendaciones';

  @override
  String get sinceYouWatchedSourceDescription =>
      'Elige la fuente de recomendaciones: kOS TV Recomienda (un algoritmo sobre tu propia biblioteca), Jellyfin Recomienda (el motor del servidor) o las métricas de similitud de TMDb.';

  @override
  String get sinceYouWatchedSourceLocal => 'kOS TV Recomienda';

  @override
  String get sinceYouWatchedSourceServer => 'Jellyfin Recomienda';

  @override
  String get sinceYouWatchedSourceOnline => 'Similitud de TMDb';

  @override
  String get sinceYouWatchedSourceType => 'Tipo de fuente';

  @override
  String get sinceYouWatchedSourceTypeDescription =>
      'Elige qué tipo de elementos recomendar';

  @override
  String get sinceYouWatchedSourceItem => 'Elemento de origen';

  @override
  String get sinceYouWatchedSourceItemDescription =>
      'Elige en qué elemento basar las recomendaciones';

  @override
  String get sinceYouWatchedRecentlyWatched => 'Vistos recientemente';

  @override
  String get sinceYouWatchedNumRows => 'Número de filas que añadir';

  @override
  String get sinceYouWatchedNumRowsDescription =>
      'Elige cuántas filas «Porque has visto» mostrar (1-5)';

  @override
  String get sinceYouWatchedIncludeWatched => 'Incluir lo ya visto';

  @override
  String get sinceYouWatchedIncludeWatchedSubtitle =>
      'Incluye elementos vistos en las recomendaciones';

  @override
  String get studiosRowSorting => 'Orden de la fila de estudios';

  @override
  String get studiosRowSortingDescription =>
      'Ordena la fila de estudios por nombre, añadidos recientemente y más.';

  @override
  String get studiosRowSortOrderDescription =>
      'Elige orden ascendente o descendente.';

  @override
  String get selectStudiosToInclude => 'Elegir estudios que incluir';

  @override
  String get selectStudiosToIncludeDescription =>
      'Elige qué estudios aparecen en la fila de Inicio.';

  @override
  String get selectAllStudios => 'Seleccionar todos';

  @override
  String get deselectAllStudios => 'Deseleccionar todos';

  @override
  String get tvStudiosFilter => 'Estudios de TV';

  @override
  String get movieStudiosFilter => 'Estudios de cine';

  @override
  String get selectedStudiosFilter => 'Estudios seleccionados';

  @override
  String get unselectedStudiosFilter => 'Estudios no seleccionados';

  @override
  String get filtersHeader => 'Filtros';

  @override
  String get showHeader => 'Mostrar';

  @override
  String get displayPlaylistsRows => 'Mostrar filas de listas de reproducción';

  @override
  String get displayPlaylistsRowsSubtitle =>
      'Mostrar las filas de listas de reproducción en las secciones de Inicio.';

  @override
  String get playlistsRowSorting =>
      'Orden de las filas de listas de reproducción';

  @override
  String get playlistsRowSortingDescription =>
      'Ordena las filas de listas de reproducción por fecha de adición, fecha de estreno, alfabéticamente y más.';

  @override
  String get playlistsRowSortOrderDescription =>
      'Ordena las filas de listas de reproducción de forma ascendente o descendente.';

  @override
  String get playlistsRowShowEpisodes => 'Mostrar episodios sueltos';

  @override
  String get playlistsRowShowEpisodesSubtitle =>
      'Despliega las series para mostrar cada episodio por separado.';

  @override
  String get displayAudioRows => 'Mostrar filas de audio';

  @override
  String get displayAudioRowsSubtitle =>
      'Mostrar las filas de audio en las secciones de Inicio.';

  @override
  String get audioRowsSorting => 'Orden de las filas de audio';

  @override
  String get audioRowsSortingDescription =>
      'Ordena las filas de audio por fecha de adición, fecha de estreno, alfabéticamente y más.';

  @override
  String get audioRowsSortOrderDescription =>
      'Ordena las filas de audio de forma ascendente o descendente.';

  @override
  String get sorting => 'Ordenación';

  @override
  String get imdbRowsSorting => 'Orden de las filas de IMDb';

  @override
  String get imdbRowsSortingDescription =>
      'Ordena las filas de IMDb por nombre, fecha de estreno, valoración y más.';

  @override
  String get imdbRowsSortOrderDescription =>
      'Ordena las filas de IMDb de forma ascendente o descendente.';

  @override
  String get tmdbRowsSorting => 'Orden de las filas de TMDb';

  @override
  String get tmdbRowsSortingDescription =>
      'Ordena las filas de TMDb por nombre, fecha de estreno, valoración y más.';

  @override
  String get tmdbRowsSortOrderDescription =>
      'Ordena las filas de TMDb de forma ascendente o descendente.';

  @override
  String get externalRowSortDefault => 'Predeterminado (orden de la lista)';

  @override
  String get externalRowSortName => 'Nombre';

  @override
  String get externalRowSortReleaseDate => 'Fecha de estreno';

  @override
  String get externalRowSortRating => 'Valoración';

  @override
  String get externalRowSortPopularity => 'Popularidad';

  @override
  String get externalRowSortShuffle => 'Aleatorio';

  @override
  String get audioPlaylists => 'Listas de reproducción de audio';

  @override
  String get appearance => 'Apariencia';

  @override
  String get layout => 'Diseño';

  @override
  String get theme => 'Tema';

  @override
  String get keyboard => 'Teclado';

  @override
  String get navButtons => 'Botones';

  @override
  String get rendering => 'Renderizado';

  @override
  String get mpvConfiguration => 'Configuración de MPV';

  @override
  String get cardSize => 'Tamaño de tarjeta';

  @override
  String get externalPlayerApp => 'Aplicación de reproductor externo';

  @override
  String get externalPlayerAppDescription =>
      'Configura un reproductor externo para activar la opción de reproducir con una pulsación larga';

  @override
  String get externalPlayerAskEachTimeSubtitle =>
      'Mostrar el selector de aplicaciones cuando comience la reproducción.';

  @override
  String get loadingInstalledPlayers => 'Cargando reproductores instalados...';

  @override
  String get connection => 'Conexión';

  @override
  String get locallyDecodedCodecs => 'Códecs decodificados localmente';

  @override
  String get transcodeTargetCodecs =>
      'Códecs de destino de la transcodificación';

  @override
  String get passthrough => 'Passthrough';

  @override
  String get supportedOnThisDevice => 'Compatible con este dispositivo';

  @override
  String get notSupportedOnThisDevice => 'No compatible con este dispositivo';

  @override
  String get mediaPlayerBehavior => 'Comportamiento del reproductor multimedia';

  @override
  String get playbackEnhancements => 'Mejoras de reproducción';

  @override
  String get replaceSkipOutroWithNextUpDisplay =>
      'Mostrar A continuación en lugar de Saltar créditos';

  @override
  String get replaceSkipOutroWithNextUpDisplaySubtitle =>
      'Muestra la superposición de A continuación en lugar del botón Saltar créditos.';

  @override
  String get playerRouting => 'Selección de reproductor';

  @override
  String get preferSoftwareDecoders => 'Preferir decodificadores de software';

  @override
  String get preferSoftwareDecodersSubtitle =>
      'Usa FFmpeg (audio) y libgav1 (AV1) antes que los decodificadores de hardware. Desactívalo si falla el passthrough de audio por HDMI.';

  @override
  String get hevcSoftwareDirectPlay =>
      'Reproducción directa de HEVC (decodificación por software)';

  @override
  String get hevcSoftwareDirectPlaySubtitle =>
      'Reproduce HEVC hasta 1080p desde el archivo original en lugar de pedir al servidor que lo transcodifique. Este Apple TV lo decodifica por software, así que los archivos de 10 bits pesados o con una tasa de bits alta pueden ir a tirones.';

  @override
  String get av1SoftwareUhdDirectPlay =>
      'Reproducción directa de AV1 en 4K (decodificación por software)';

  @override
  String get av1SoftwareUhdDirectPlaySubtitle =>
      'Reproduce AV1 por encima de 1080p, incluido HDR10, desde el archivo original en lugar de pedir al servidor que lo transcodifique. Este dispositivo decodifica AV1 por software, así que los archivos 4K pesados o con una tasa de bits alta pueden ir a tirones.';

  @override
  String get cadenceSlowdown => '24 fps suaves en una tele de 60 Hz';

  @override
  String get cadenceSlowdownSubtitle =>
      'Cuando Ajustar frecuencia de fotogramas está desactivado, reproduce el vídeo de 24 fps un 0,1 % más lento para que encaje en la tele sin perder fotogramas. No se usa cuando el audio pasa directamente a un receptor.';

  @override
  String get cadenceTipTitle => 'Activa Ajustar frecuencia de fotogramas';

  @override
  String get cadenceTipMessage =>
      'Este vídeo no se puede reproducir con fluidez a la frecuencia de actualización actual de tu tele. En tu Apple TV, abre Ajustes > Vídeo y audio > Ajustar contenido y activa Ajustar frecuencia de fotogramas.';

  @override
  String get cadenceTipSlowdownHint =>
      'O activa 24 fps suaves en una tele de 60 Hz en kOS TV, en Reproducción > Calidad y decodificación.';

  @override
  String get useExternalPlayer => 'Usar siempre el reproductor externo';

  @override
  String get useExternalPlayerSubtitle =>
      'Abre la reproducción de vídeo en la aplicación externa que elijas en Android TV.';

  @override
  String get externalPlayerLiveTvOnly => 'Solo TV en directo';

  @override
  String get externalPlayerLiveTvOnlySubtitle =>
      'Usa el reproductor externo para la TV en directo y el reproductor integrado para todo lo demás.';

  @override
  String get automaticQueuing => 'Cola automática';

  @override
  String get preferSdhSubtitles => 'Preferir subtítulos SDH';

  @override
  String get preferSdhSubtitlesSubtitle =>
      'Da prioridad a las pistas de subtítulos SDH/CC en la selección automática.';

  @override
  String get preferTextSubtitles => 'Preferir subtítulos de texto';

  @override
  String get preferTextSubtitlesSubtitle =>
      'Da prioridad a los subtítulos de texto (SRT, VTT) frente a los de imagen (PGS, VobSub).';

  @override
  String get preferExternalSubtitles => 'Preferir subtítulos externos';

  @override
  String get preferExternalSubtitlesSubtitle =>
      'Da prioridad a los archivos de subtítulos externos frente a las pistas incrustadas.';

  @override
  String get webDiagnostics => 'Diagnóstico web';

  @override
  String get webDiagnosticsTitle => 'Diagnóstico web de kOS TV';

  @override
  String get webDiagnosticsIntro =>
      'Usa esta página para diagnosticar problemas de conexión del navegador (CORS, contenido mixto y ajustes de descubrimiento).';

  @override
  String get webDiagnosticsDetectedMixedContentFailure =>
      'Error de contenido mixto detectado';

  @override
  String get webDiagnosticsDetectedCorsPreflightFailure =>
      'Fallo de CORS/verificación previa detectado';

  @override
  String get webDiagnosticsMixedContentFailureBody =>
      'kOS TV ha detectado una página HTTPS que intentaba llamar a una URL HTTP del servidor. Los navegadores bloquean esta solicitud antes de que llegue a tu servidor.';

  @override
  String get webDiagnosticsCorsFailureBody =>
      'kOS TV ha detectado un fallo de la solicitud en el navegador, que suele deberse a que faltan las cabeceras CORS o de verificación previa en el servidor multimedia.';

  @override
  String webDiagnosticsTargetUrl(String url) {
    return 'URL de destino: $url';
  }

  @override
  String webDiagnosticsDetail(String detail) {
    return 'Detalle: $detail';
  }

  @override
  String get webDiagnosticsCurrentRuntimeContext =>
      'Contexto de tiempo de ejecución actual';

  @override
  String get webDiagnosticsOrigin => 'Origen';

  @override
  String get webDiagnosticsScheme => 'Esquema';

  @override
  String get webDiagnosticsPluginMode => 'Modo complemento';

  @override
  String get webDiagnosticsWebRtcScan => 'Escaneo WebRTC';

  @override
  String get webDiagnosticsForcedServerUrl => 'URL de servidor forzada';

  @override
  String get webDiagnosticsDefaultServerUrl => 'URL de servidor predeterminada';

  @override
  String get webDiagnosticsDiscoveryProxyUrl =>
      'URL del proxy de descubrimiento';

  @override
  String get notConfigured => 'no configurado';

  @override
  String get webDiagnosticsMixedContent => 'Contenido mixto';

  @override
  String get webDiagnosticsMixedContentDetected =>
      'Esta página se carga a través de HTTPS, pero una o más URL configuradas son HTTP. Los navegadores impiden que las páginas HTTPS llamen a las API HTTP.';

  @override
  String get webDiagnosticsMixedContentFix =>
      'Solución: sirve tu servidor multimedia o el proxy por HTTPS, o carga kOS TV por HTTP solo en redes locales de confianza.';

  @override
  String get webDiagnosticsNoMixedContentDetected =>
      'No se ha detectado ninguna configuración evidente de contenido mixto en los ajustes actuales.';

  @override
  String get webDiagnosticsCorsChecklist => 'Lista de verificación CORS';

  @override
  String get webDiagnosticsCorsChecklistItem1 =>
      '• Permitir el origen del navegador en Access-Control-Allow-Origin.';

  @override
  String get webDiagnosticsCorsChecklistItem2 =>
      '• Incluir Authorization, X-Emby-Authorization y X-Emby-Token en Access-Control-Allow-Headers.';

  @override
  String get webDiagnosticsCorsChecklistItem3 =>
      '• Exponer Content-Range y Accept-Ranges para la transmisión y para avanzar o retroceder.';

  @override
  String get webDiagnosticsCorsChecklistItem4 =>
      '• Devolver 204 a las solicitudes de verificación previa OPTIONS.';

  @override
  String get webDiagnosticsHeaderSnippetTitle =>
      'Ejemplo de cabeceras (estilo nginx)';

  @override
  String get note => 'Nota';

  @override
  String get webDiagnosticsNonWebNote =>
      'Esta ruta de diagnóstico está pensada para las versiones web. Si ves esto en otra plataforma, puede que estas comprobaciones no sean aplicables.';

  @override
  String get backToServerSelect => 'Volver a la selección de servidor';

  @override
  String get signOutAllUsers => 'Cerrar sesión de todos los usuarios';

  @override
  String get voiceSearchPermissionPermanentlyDenied =>
      'El permiso del micrófono está denegado de forma permanente. Actívalo en los ajustes del sistema.';

  @override
  String get voiceSearchPermissionRequired =>
      'Se requiere permiso del micrófono para la búsqueda por voz.';

  @override
  String get voiceSearchNoMatch => 'No te he entendido. Inténtalo de nuevo.';

  @override
  String get voiceSearchNoSpeechDetected => 'No se detectó ninguna voz.';

  @override
  String get voiceSearchMicrophoneError => 'Error de micrófono.';

  @override
  String get voiceSearchNeedsInternet =>
      'La búsqueda por voz necesita Internet.';

  @override
  String get voiceSearchServiceBusy =>
      'El servicio de voz está ocupado. Inténtalo de nuevo.';

  @override
  String get microphonePermissionPermanentlyDenied =>
      'El permiso del micrófono está denegado de forma permanente.';

  @override
  String get microphonePermissionDenied =>
      'Se ha denegado el permiso del micrófono.';

  @override
  String get speechRecognitionUnavailable =>
      'El reconocimiento de voz no está disponible en este dispositivo.';

  @override
  String get openIosRoutePicker => 'Abrir el selector de rutas de iOS';

  @override
  String get airPlayRoutePickerUnavailable =>
      'El selector de rutas de AirPlay no está disponible en este dispositivo.';

  @override
  String get videos => 'Vídeos';

  @override
  String get programs => 'Programas';

  @override
  String get songs => 'Canciones';

  @override
  String get photoAlbums => 'Álbumes de fotos';

  @override
  String get photos => 'Fotos';

  @override
  String get people => 'Personas';

  @override
  String get recentlyReleasedEpisodes => 'Episodios estrenados recientemente';

  @override
  String get watchAgain => 'Ver de nuevo';

  @override
  String get guestAppearances => 'Apariciones como invitado';

  @override
  String get personWebsite => 'Web oficial';

  @override
  String get watchWithGroup => 'Ver juntos';

  @override
  String get watchPartyGroupSubtitles => 'Subtítulos para todos';

  @override
  String get watchPartyOwnSubtitles => 'Que cada uno elija';

  @override
  String get watchPartyLobby => 'En la sala de espera';

  @override
  String get watchPartyUpNextLabel => 'A continuación';

  @override
  String get watchPartyRoomSettings => 'Ajustes de la sala';

  @override
  String get watchPartyCodeOrLink => 'Código de sala o enlace de invitación';

  @override
  String get watchPartyCopyInvite => 'Copiar enlace de invitación';

  @override
  String get watchPartyInviteCopied => 'Enlace de invitación copiado';

  @override
  String get watchPartyLetEveryoneVote => 'Que todos voten las películas';

  @override
  String get watchPartyVoteHelp =>
      'Añade películas para que todos voten y luego pon la que quieras. Los episodios de series los sigues eligiendo tú.';

  @override
  String get watchPartyGuestVoteHelp =>
      'Vota lo que quieres ver. El anfitrión pone una.';

  @override
  String get watchPartySearchMovies => 'Buscar películas';

  @override
  String get watchPartyNoSuggestions => 'Aún no hay películas para votar.';

  @override
  String get watchPartySuggested => 'Añadida a la votación de Ver juntos';

  @override
  String watchPartyVoteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count votos',
      one: '$count voto',
    );
    return '$_temp0';
  }

  @override
  String get watchParty => 'Ver juntos';

  @override
  String get watchPartyUnavailable => 'Este servidor no ofrece Ver juntos.';

  @override
  String get watchPartyRoomCode => 'Código de sala';

  @override
  String get watchPartyStart => 'Abrir una sala de Ver juntos';

  @override
  String get watchPartyPickTitle =>
      'Abre un título y elige Ver con grupo para decidir qué veis todos.';

  @override
  String get watchPartyWaitingForHost =>
      'Esperando a que el anfitrión elija algo.';

  @override
  String get watchPartyShareCode =>
      'Los demás se unen con este código desde su pantalla de Ver juntos.';

  @override
  String get watchPartyReconnecting => 'Reconectando...';

  @override
  String get watchPartyOffline => 'desconectado';

  @override
  String get watchPartyStartForEveryone => 'Empezar para todos';

  @override
  String watchPartyResumeAt(String time) {
    return 'Reanudar en $time';
  }

  @override
  String get watchPartyStartFromBeginning => 'Empezar desde el principio';

  @override
  String watchPartyResumeWhere(String name) {
    return 'Donde lo dejó $name, quien menos ha avanzado de la sala.';
  }

  @override
  String get watchPartyResumeEarliest =>
      'Donde lo dejó quien menos ha avanzado de la sala.';

  @override
  String get watchPartyResumeYours =>
      'Donde lo dejaste. Todos empiezan desde ahí.';

  @override
  String watchPartyResumeNotStarted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personas aún no lo han empezado.',
      one: '1 persona aún no lo ha empezado.',
    );
    return '$_temp0';
  }

  @override
  String get watchPartyBackToLobby => 'Volver a la sala de espera';

  @override
  String get watchPartyGuestsCanPause =>
      'Los invitados pueden reproducir y pausar';

  @override
  String get watchPartyEnd => 'Terminar para todos';

  @override
  String get watchPartyEnded => 'La sala de Ver juntos se ha cerrado.';

  @override
  String get watchPartyStaged => 'Elegido para Ver juntos';

  @override
  String watchPartyUpNext(String title) {
    return 'A continuación: $title';
  }

  @override
  String get watchParties => 'Ver juntos';

  @override
  String get watchPartyStartWith => 'Crear salas con';

  @override
  String get watchPartyServiceMoonbaseHint =>
      'Chat, reacciones y votaciones. Funciona con el complemento del servidor.';

  @override
  String get watchPartyServiceSyncPlayHint =>
      'El propio de Jellyfin. Pueden unirse amigos desde otras apps de Jellyfin.';

  @override
  String get watchPartyServiceNote =>
      'Puedes unirte a salas de los dos tipos. Esto solo elige las que creas tú.';

  @override
  String get watchPartyDuringParty => 'Dentro de una sala';

  @override
  String get watchPartyChatOverlay => 'Mostrar el chat sobre el vídeo';

  @override
  String get watchPartyChatOverlaySubtitle =>
      'Los mensajes nuevos se muestran unos segundos';

  @override
  String get watchPartyAlerts => 'Avisos de salas';

  @override
  String get watchPartyAlertsSubtitle =>
      'Avisarme cuando alguien de este servidor abra una';

  @override
  String get watchPartyJoinWithCode => 'Unirse con un código';

  @override
  String get watchPartyOnThisServer => 'En este servidor';

  @override
  String watchPartyCountOnServer(int count) {
    return '$count en este servidor';
  }

  @override
  String get watchPartyRoomsHint =>
      'Para unirte necesitas acceso al título. Una sala se cierra cuando se va la última persona.';

  @override
  String get watchPartyRoomsEmpty =>
      'Aquí aparecen las salas a las que puedes unirte. ¿Te han pasado un código? Elige Unirse con un código.';

  @override
  String get watchPartyPasteHint =>
      'También puedes pegar aquí un enlace de invitación. En un móvil, el enlace abre kOS TV directamente en la sala.';

  @override
  String watchPartyWatchingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count viendo',
      one: '$count viendo',
    );
    return '$_temp0';
  }

  @override
  String watchPartyHostsParty(String name) {
    return 'Sala de $name';
  }

  @override
  String get watchPartyEveryoneControlsShort => 'Todos controlan';

  @override
  String get watchPartyVotingNow => 'Votando qué ver';

  @override
  String get watchPartyNeedsMoonbase =>
      'Ver juntos necesita el complemento de kOS TV para el servidor';

  @override
  String get watchPartyNeedsMoonbaseHint =>
      'Pide a quien administre el servidor que instale el complemento de kOS TV para el servidor. En Jellyfin, SyncPlay sigue funcionando sin él.';

  @override
  String get watchPartyWrongPin =>
      'Ese PIN no es correcto. Inténtalo de nuevo.';

  @override
  String get watchPartyTooManyTries => 'Demasiados intentos. Espera un minuto.';

  @override
  String get watchPartyFull => 'Esta sala está llena.';

  @override
  String get watchPartyNoSuchCode => 'No hay ninguna sala con ese código.';

  @override
  String get watchPartyNoAccess => 'No tienes acceso a lo que están viendo.';

  @override
  String get watchPartyRemoved => 'El anfitrión te ha sacado de la sala.';

  @override
  String get watchPartyYours => 'Tu sala de Ver juntos';

  @override
  String get watchPartyInviteHint =>
      'Pégalo en cualquier chat. Abre una página de este servidor con un botón que abre la app.';

  @override
  String get watchPartySendInvite => 'Envía la invitación';

  @override
  String get watchPartyScanInvite =>
      'Escanéalo con el móvil para obtener el enlace de invitación y envíalo desde allí. O comparte el código sin más.';

  @override
  String get watchPartyStartsTogether =>
      'La reproducción espera a que estén listos los reproductores de todos, 10 segundos como mucho, y luego cuenta 3, 2, 1.';

  @override
  String get watchPartyStatusInSync => 'Sincronizado';

  @override
  String get watchPartyStatusCatchingUp => 'Poniéndose al día';

  @override
  String get watchPartyStatusBuffering => 'Cargando';

  @override
  String get watchPartyStatusNotWatching => 'No está viendo';

  @override
  String get watchPartyStatusReady => 'Listo';

  @override
  String get watchPartyStatusJoining => 'Uniéndose';

  @override
  String get watchPartyHost => 'Anfitrión';

  @override
  String watchPartyWaitingFor(String name) {
    return 'Esperando al reproductor de $name';
  }

  @override
  String watchPartyWaitingForCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Esperando a $count reproductores',
      one: 'Esperando a $count reproductor',
    );
    return '$_temp0';
  }

  @override
  String watchPartyStartingAnyway(int seconds) {
    return 'Empezando igualmente en $seconds s';
  }

  @override
  String get watchPartyStartingTogether => 'Empezando a la vez';

  @override
  String watchPartyToastPaused(String name) {
    return '$name ha pausado';
  }

  @override
  String watchPartyToastResumed(String name) {
    return '$name ha reanudado';
  }

  @override
  String watchPartyToastSkipped(String name, String time) {
    return '$name ha saltado a $time';
  }

  @override
  String watchPartyToastJoined(String name) {
    return '$name se ha unido';
  }

  @override
  String watchPartyToastLeft(String name) {
    return '$name se ha ido';
  }

  @override
  String watchPartyToastSwitched(String name, String title) {
    return '$name ha cambiado a $title';
  }

  @override
  String get watchPartyToastYouAreHost => 'Ahora eres el anfitrión';

  @override
  String watchPartyToastNewHost(String name) {
    return '$name es ahora el anfitrión';
  }

  @override
  String get watchPartyToastEveryoneControls =>
      'Ahora todos pueden controlar la reproducción';

  @override
  String get watchPartyToastHostControls =>
      'Ahora solo el anfitrión controla la reproducción';

  @override
  String get watchPartyOnlyHostControls =>
      'Solo el anfitrión puede controlar la reproducción.';

  @override
  String get watchPartyToastReconnecting => 'Reconectando con la sala...';

  @override
  String get watchPartyToastReconnected => 'De vuelta en la sala';

  @override
  String watchPartyToastEnded(String name) {
    return '$name ha cerrado la sala';
  }

  @override
  String get watchPartyChat => 'Chat';

  @override
  String get watchPartySendToParty => 'Enviar a la sala';

  @override
  String get watchPartyBackToClose => 'Atrás para cerrar';

  @override
  String get watchPartyType => 'Escribir';

  @override
  String get watchPartyReplyHaha => 'Jaja';

  @override
  String get watchPartyReplyNoWay => '¡No puede ser!';

  @override
  String get watchPartyReplyPausePlease => 'Pausa, por favor';

  @override
  String get watchPartyReplyBrb => 'Ahora vuelvo';

  @override
  String get watchPartyReplyAgain => '¡Otra vez!';

  @override
  String get watchPartyReactionLove => 'Me encanta';

  @override
  String get watchPartyReactionHaha => 'Jaja';

  @override
  String get watchPartyReactionWow => 'Guau';

  @override
  String get watchPartyReactionSad => 'Triste';

  @override
  String get watchPartyReactionFire => 'Fuego';

  @override
  String get watchPartyReactionPopcorn => 'Palomitas';

  @override
  String get watchPartyMakeHost => 'Hacer anfitrión';

  @override
  String get watchPartyEveryoneControls =>
      'Todos pueden controlar la reproducción';

  @override
  String get watchPartyEveryoneControlsHint =>
      'Cualquiera puede reproducir, pausar y saltar';

  @override
  String get watchPartyRoomPin => 'PIN de la sala';

  @override
  String get watchPartyRoomPinHint => 'Pedir un PIN antes de que alguien entre';

  @override
  String get watchPartyPinDigits => 'De 4 a 8 dígitos';

  @override
  String get watchPartyLeave => 'Salir';

  @override
  String watchPartyLeaveHandsOver(String name) {
    return 'Salir · $name será el anfitrión';
  }

  @override
  String watchPartyStartedBy(String name) {
    return '$name ha abierto una sala de Ver juntos';
  }

  @override
  String watchPartyInLobbyCount(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$title · $count en la sala de espera',
      one: '$title · $count en la sala de espera',
    );
    return '$_temp0';
  }

  @override
  String get watchPartyFirstOnHome =>
      'Aparece la primera en Ver juntos, en Inicio';

  @override
  String watchPartyAddServerQuestion(String address) {
    return 'Esta invitación es para un servidor que aún no has añadido, $address. Añádelo e inicia sesión para unirte.';
  }

  @override
  String get disk => 'Disco';

  @override
  String get openInBrowser => 'Abrir en el navegador';

  @override
  String get achievementBadges => 'Insignias de logros';

  @override
  String get achievementsBadges => 'Insignias';

  @override
  String achievementsBadgeCount(int unlocked, int total) {
    return '$unlocked de $total insignias';
  }

  @override
  String get achievementsUnlockToasts => 'Avisos de desbloqueo';

  @override
  String get achievementsUnlockToastsSubtitle =>
      'Muestra un aviso cuando desbloqueas una insignia';

  @override
  String get achievementsUnlockedNotification => 'Logro desbloqueado';

  @override
  String achievementsUnlockedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count logros desbloqueados',
      one: '$count logro desbloqueado',
    );
    return '$_temp0';
  }

  @override
  String achievementsUnlockedMore(int count) {
    return '+$count más';
  }

  @override
  String get achievementsQuests => 'Misiones';

  @override
  String achievementsQuestCount(int count) {
    return '$count completadas';
  }

  @override
  String get achievementsLeaderboard => 'Clasificación';

  @override
  String get achievementsLeaderboardSubtitle =>
      'Cómo vas frente a otros usuarios de este servidor';

  @override
  String get achievementsRecap => 'Resumen';

  @override
  String get achievementsRecapSubtitle => 'Lo que has visto últimamente';

  @override
  String get achievementsLibraryCompletion => 'Progreso de las bibliotecas';

  @override
  String achievementsLibraryCount(int count) {
    return '$count bibliotecas';
  }

  @override
  String achievementsScore(int score) {
    return '$score puntos';
  }

  @override
  String get achievementsScoreLabel => 'Puntuación';

  @override
  String get achievementsTopRank => 'Rango máximo alcanzado';

  @override
  String achievementsPointsToNextRank(int points, String tier) {
    return '$points puntos para $tier';
  }

  @override
  String achievementsCurrentStreak(int days) {
    return 'Racha de $days días';
  }

  @override
  String achievementsBestStreak(int days) {
    return 'Mejor: $days días';
  }

  @override
  String get achievementsShowcase => 'Vitrina';

  @override
  String get achievementsUnlocked => 'Desbloqueadas';

  @override
  String get achievementsLocked => 'Bloqueadas';

  @override
  String get achievementsNothingHere => 'Aún no hay nada.';

  @override
  String get achievementsHiddenBadge => 'Logro oculto';

  @override
  String achievementsUnlockedOn(String date) {
    return 'Desbloqueada el $date';
  }

  @override
  String achievementsPoints(int points) {
    return '$points pts';
  }

  @override
  String get achievementsDailyQuests => 'Diarias';

  @override
  String get achievementsWeeklyQuests => 'Semanales';

  @override
  String achievementsQuestReward(int points) {
    return '+$points';
  }

  @override
  String get achievementsRerollDaily => 'Cambiar misiones diarias';

  @override
  String get achievementsRerollWeekly => 'Cambiar misiones semanales';

  @override
  String get achievementsRerollOffer => 'Cambia este grupo por otro distinto';

  @override
  String get achievementsRerollSpentDaily =>
      'Usado hoy, vuelve a medianoche UTC';

  @override
  String get achievementsRerollSpentWeekly =>
      'Usado esta semana, vuelve el lunes UTC';

  @override
  String get achievementsRerollConfirm => '¿Cambiar estas misiones?';

  @override
  String get achievementsRerollConfirmBody =>
      'Tienes un cambio diario y uno semanal, y esto lo gasta.';

  @override
  String get achievementsRerollFailed =>
      'No se han podido cambiar esas misiones.';

  @override
  String get achievementsSuggested => 'Sugerencias para ver';

  @override
  String get achievementsNoSuggestions =>
      'No hay sugerencias para esta insignia.';

  @override
  String get achievementsProgressLabel => 'Progreso';

  @override
  String get achievementsLoadout => 'Inventario';

  @override
  String get achievementsLoadoutSubtitle =>
      'Puntos para gastar y las mejoras que tienes';

  @override
  String get achievementsAppearance => 'Apariencia';

  @override
  String get achievementsAppearanceSubtitle =>
      'El avatar y el título de tu perfil';

  @override
  String get achievementsAvatars => 'Avatares';

  @override
  String get achievementsTitles => 'Títulos';

  @override
  String get achievementsEquipped => 'Equipado';

  @override
  String get achievementsOwned => 'Conseguido';

  @override
  String achievementsEarnedAt(int score) {
    return 'Se gana al llegar a $score puntos en total';
  }

  @override
  String get achievementsAppearanceEmpty =>
      'Este servidor no tiene avatares ni títulos para usar.';

  @override
  String get achievementsAppearanceFailed =>
      'No se ha podido cambiar el aspecto del perfil.';

  @override
  String get achievementsPowerUps => 'Potenciadores';

  @override
  String get achievementsStats => 'Estadísticas';

  @override
  String get achievementsStatsSubtitle => 'Tus récords y cómo va el servidor';

  @override
  String get achievementsStatsWatched => 'Visto';

  @override
  String get achievementsStatsBests => 'Récords';

  @override
  String get achievementsStatsHabits => 'Hábitos';

  @override
  String get achievementsStatsVariety => 'Variedad';

  @override
  String get achievementsStatsServer => 'Este servidor';

  @override
  String get achievementsStatsClock => 'Cuándo ves';

  @override
  String get achievementsStatItems => 'Elementos vistos';

  @override
  String get achievementsStatMovies => 'Películas vistas';

  @override
  String get achievementsStatSeries => 'Series terminadas';

  @override
  String get achievementsStatHours => 'Horas vistas';

  @override
  String get achievementsStatDays => 'Días viendo';

  @override
  String get achievementsStatRewatches => 'Vistos otra vez';

  @override
  String get achievementsStatBestWatchStreak => 'Mejor racha viendo';

  @override
  String get achievementsStatBestLoginStreak => 'Mejor racha de accesos';

  @override
  String get achievementsStatMostEpisodes => 'Más episodios en un día';

  @override
  String get achievementsStatMostMovies => 'Más películas en un día';

  @override
  String get achievementsStatLongestItem => 'Elemento más largo';

  @override
  String get achievementsStatBestCombo => 'Mejor combo';

  @override
  String get achievementsStatLateNight => 'Sesiones nocturnas';

  @override
  String get achievementsStatEarlyMorning => 'Sesiones a primera hora';

  @override
  String get achievementsStatWeekend => 'Sesiones en fin de semana';

  @override
  String get achievementsStatDaysSignedIn => 'Días con sesión iniciada';

  @override
  String get achievementsStatLibraries => 'Bibliotecas visitadas';

  @override
  String get achievementsStatGenres => 'Géneros vistos';

  @override
  String get achievementsStatDecades => 'Décadas vistas';

  @override
  String get achievementsStatCountries => 'Países vistos';

  @override
  String get achievementsStatLanguages => 'Idiomas vistos';

  @override
  String get achievementsStatUsers => 'Usuarios';

  @override
  String get achievementsStatBadgesUnlocked => 'Insignias desbloqueadas';

  @override
  String get achievementsStatScoreEarned => 'Puntos ganados';

  @override
  String get achievementsStatCommonBadge => 'Insignia más común';

  @override
  String get achievementsActivity => 'Actividad';

  @override
  String get achievementsActivitySubtitle =>
      'Lo que se ha desbloqueado últimamente en el servidor';

  @override
  String achievementsActivityUnlocked(String user, String badge) {
    return '$user ha desbloqueado $badge';
  }

  @override
  String get achievementsShop => 'Tienda';

  @override
  String get achievementsShopSubtitle => 'Gasta puntos en más mejoras';

  @override
  String achievementsShopPack(String name, int count) {
    return '$name ×$count';
  }

  @override
  String get achievementsShopEmpty => 'No hay nada a la venta ahora mismo.';

  @override
  String get achievementsBuyConfirm => '¿Comprar esto?';

  @override
  String get achievementsBuyConfirmBody =>
      'Se descuenta directamente de tu saldo de puntos.';

  @override
  String get achievementsBuyFailed => 'No se ha podido comprar.';

  @override
  String get achievementsScoreBank => 'Saldo de puntos';

  @override
  String get achievementsBoost => 'Impulso de XP';

  @override
  String get achievementsBoostBody =>
      'Duplica los puntos durante una hora. Si lo vuelves a usar, la hora empieza de nuevo.';

  @override
  String get achievementsDoubleCredit => 'Crédito doble';

  @override
  String get achievementsDoubleCreditBody =>
      'Lo próximo que termines cuenta el doble para las insignias.';

  @override
  String get achievementsStreakFreeze => 'Congelar racha';

  @override
  String get achievementsStreakFreezeBody =>
      'Cubre un día perdido. Solo puedes guardar uno.';

  @override
  String achievementsPowerUpHeld(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tienes $count',
      one: 'Tienes 1',
      zero: 'No tienes ninguno',
    );
    return '$_temp0';
  }

  @override
  String get achievementsPowerUpActive => 'Activo ahora';

  @override
  String get achievementsUsePowerUp => '¿Usar este potenciador?';

  @override
  String get achievementsUsePowerUpBody => 'Se gasta en cuanto confirmes.';

  @override
  String get achievementsPowerUpFailed =>
      'No se ha podido usar ese potenciador.';

  @override
  String get achievementsHours => 'Horas';

  @override
  String get achievementsStreak => 'Racha';

  @override
  String get achievementsPeriodWeek => 'Semana';

  @override
  String get achievementsPeriodMonth => 'Mes';

  @override
  String get achievementsPeriodYear => 'Año';

  @override
  String achievementsDaysWatched(int count) {
    return '$count días viendo';
  }

  @override
  String achievementsBadgesEarned(int count) {
    return '$count insignias ganadas';
  }

  @override
  String get achievementsTopDirectors => 'Directores más vistos';

  @override
  String get achievementsTopActors => 'Actores más vistos';

  @override
  String get achievementsLoadFailed => 'No se han podido cargar tus logros.';

  @override
  String get friends => 'Amigos';

  @override
  String get friendsSubtitle =>
      'Mira quién está en línea y chatea con la gente de este servidor';

  @override
  String get friendsShowButton => 'Mostrar botón de amigos';

  @override
  String get friendsShowButtonSubtitle =>
      'Amigos y chat del complemento Achievement Badges';

  @override
  String get friendsMessages => 'Mensajes';

  @override
  String friendsUnreadCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mensajes sin leer',
      one: '1 mensaje sin leer',
      zero: 'No hay mensajes sin leer',
    );
    return '$_temp0';
  }

  @override
  String get friendsRequests => 'Solicitudes de amistad';

  @override
  String friendsRequestCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count esperándote',
      one: '1 esperándote',
      zero: 'Nada pendiente',
    );
    return '$_temp0';
  }

  @override
  String get friendsAdd => 'Añadir amigos';

  @override
  String get friendsAddSubtitle => 'Busca gente de este servidor';

  @override
  String get friendsPrivacy => 'Privacidad';

  @override
  String get friendsPrivacySubtitle => 'Lo que pueden ver tus amigos';

  @override
  String get friendsOnline => 'En línea';

  @override
  String get friendsOffline => 'Desconectado';

  @override
  String get friendsNone =>
      'Aún no tienes amigos. Añade gente de este servidor para verla aquí.';

  @override
  String friendsWatching(String title) {
    return 'Viendo $title';
  }

  @override
  String friendsLastWatched(String title) {
    return 'Lo último que vio: $title';
  }

  @override
  String friendsLastSeen(String time) {
    return 'Visto por última vez $time';
  }

  @override
  String get friendsLoadFailed =>
      'No se ha podido cargar. Comprueba la conexión y vuelve a intentarlo.';

  @override
  String get friendsActionFailed =>
      'No ha funcionado. Vuelve a intentarlo en un momento.';

  @override
  String get friendsIncoming => 'Esperándote';

  @override
  String get friendsOutgoing => 'Enviadas por ti';

  @override
  String get friendsNoRequests => 'No hay solicitudes de amistad.';

  @override
  String get friendsAccept => 'Aceptar';

  @override
  String get friendsDecline => 'Rechazar';

  @override
  String get friendsCancelRequest => 'Cancelar solicitud';

  @override
  String friendsRequestFrom(String name) {
    return '$name te ha enviado una solicitud de amistad';
  }

  @override
  String friendsCancelRequestBody(String name) {
    return '¿Retirar la solicitud que enviaste a $name?';
  }

  @override
  String get friendsSearchHint => 'Buscar personas';

  @override
  String get friendsNoMatches => 'Nadie coincide con ese nombre.';

  @override
  String friendsRequestSent(String name) {
    return 'Solicitud enviada a $name';
  }

  @override
  String get friendsSendRequest => 'Añadir como amigo';

  @override
  String get friendsSendMessage => 'Enviar mensaje';

  @override
  String friendsOpenItem(String title) {
    return 'Abrir $title';
  }

  @override
  String get friendsRemove => 'Eliminar amigo';

  @override
  String friendsRemoveBody(String name) {
    return '¿Quitar a $name de tus amigos? Podrás volver a enviarle una solicitud más tarde.';
  }

  @override
  String get friendsBlock => 'Bloquear';

  @override
  String get friendsUnblock => 'Desbloquear';

  @override
  String friendsBlockBody(String name) {
    return '¿Bloquear a $name? Ninguno de los dos podrá enviar mensajes directos al otro. Los chats de grupo en común siguen abiertos.';
  }

  @override
  String friendsUnblockBody(String name) {
    return '¿Desbloquear a $name?';
  }

  @override
  String get friendsBlocked => 'Usuarios bloqueados';

  @override
  String friendsProfileHidden(String name) {
    return '$name tiene su perfil en privado.';
  }

  @override
  String get friendsAppearOffline => 'Aparecer desconectado';

  @override
  String get friendsAppearOfflineSubtitle =>
      'Tus amigos siempre te verán desconectado';

  @override
  String get friendsHideNowPlaying => 'Ocultar lo que estoy viendo';

  @override
  String get friendsHideNowPlayingSubtitle =>
      'Tus amigos te ven en línea, pero no lo que estás viendo';

  @override
  String get friendsHideLastWatched => 'Ocultar lo último que he visto';

  @override
  String get friendsHideLastWatchedSubtitle =>
      'Tus amigos no verán lo último que viste mientras estés desconectado';

  @override
  String get friendsMessageNotifications => 'Avisos de mensajes';

  @override
  String get friendsMessageNotificationsSubtitle =>
      'Muestra un aviso cuando un amigo te escribe';

  @override
  String get friendsMuteDuringPlayback => 'Silenciar durante la reproducción';

  @override
  String get friendsMuteDuringPlaybackSubtitle =>
      'Sin avisos de mensajes mientras se reproduce un vídeo o un juego';

  @override
  String get friendsSaveFailed => 'No se han podido guardar tus ajustes.';

  @override
  String get chatNew => 'Mensaje nuevo';

  @override
  String get chatNewSubtitle => 'Empieza un chat con un amigo';

  @override
  String get chatNewGroup => 'Grupo nuevo';

  @override
  String get chatNewGroupSubtitle => 'Chatea con varios amigos a la vez';

  @override
  String get chatNone => 'Aún no hay mensajes.';

  @override
  String get chatYou => 'Tú';

  @override
  String chatYouSaid(String text) {
    return 'Tú: $text';
  }

  @override
  String get chatPhoto => 'Foto';

  @override
  String get chatEmoji => 'Emoji';

  @override
  String get chatEmojiSearch => 'Buscar emoji';

  @override
  String get chatNoRecentEmoji => 'No hay emojis recientes';

  @override
  String get chatViewPhoto => 'Ver foto';

  @override
  String get chatHint => 'Escribe un mensaje';

  @override
  String get chatAttach => 'Enviar una foto';

  @override
  String get chatEdited => 'editado';

  @override
  String get chatSeen => 'Visto';

  @override
  String get chatSent => 'Enviado';

  @override
  String get chatEditing => 'Editando mensaje';

  @override
  String get chatMessageOptions => 'Opciones del mensaje';

  @override
  String get chatDeleteBody => '¿Eliminar este mensaje para todos?';

  @override
  String get chatClear => 'Vaciar conversación';

  @override
  String get chatClearBody =>
      '¿Eliminar todos los mensajes de este chat para todos sus miembros?';

  @override
  String get chatGroupInfo => 'Información del grupo';

  @override
  String get chatGroupName => 'Nombre del grupo';

  @override
  String chatMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count miembros',
      one: '1 miembro',
    );
    return '$_temp0';
  }

  @override
  String get chatOwner => 'Propietario';

  @override
  String get chatAdmin => 'Administrador';

  @override
  String get chatMakeAdmin => 'Hacer administrador';

  @override
  String get chatRemoveAdmin => 'Quitar administrador';

  @override
  String get chatRemoveMember => 'Quitar del grupo';

  @override
  String get chatAddMember => 'Añadir personas';

  @override
  String get chatNobodyToAdd => 'No queda nadie por añadir.';

  @override
  String get chatLeave => 'Salir del grupo';

  @override
  String get chatLeaveBody =>
      '¿Salir de este grupo? Alguien tendrá que volver a añadirte para que entres de nuevo.';

  @override
  String get chatCreate => 'Crear grupo';

  @override
  String get chatPickMembers => 'Elige al menos dos amigos';

  @override
  String chatNewMessageFrom(String name) {
    return 'Mensaje nuevo de $name';
  }

  @override
  String get chatImageTooLarge => 'Esa imagen pesa más de 8 MB.';

  @override
  String get chatImageUnsupported =>
      'Solo se pueden enviar imágenes PNG, JPEG, GIF y WebP.';

  @override
  String get embeddedBrowserNotAvailable =>
      'El navegador integrado no está disponible en esta plataforma.';

  @override
  String get adminRestartServerConfirmation =>
      '¿Seguro que quieres reiniciar el servidor?';

  @override
  String get adminShutdownServerConfirmation =>
      '¿Seguro que quieres apagar el servidor? Tendrás que volver a iniciarlo a mano.';

  @override
  String get internal => 'Interno';

  @override
  String get idle => 'Inactivo';

  @override
  String get os => 'SO';

  @override
  String get adminNoUsersFound => 'No se encontraron usuarios';

  @override
  String get adminNoUsersMatchSearch =>
      'Ningún usuario coincide con tu búsqueda';

  @override
  String get adminNoDevicesFound => 'No se encontraron dispositivos';

  @override
  String get adminNoDevicesMatchCurrentFilters =>
      'Ningún dispositivo coincide con los filtros actuales';

  @override
  String get remoteAccess => 'Acceso remoto';

  @override
  String get localOnly => 'Solo local';

  @override
  String get adminMediaAnalyticsLoadFailed =>
      'No se pudieron cargar las analíticas multimedia';

  @override
  String get analyticsCombinedAcrossLibraries =>
      'Analíticas combinadas de todas las bibliotecas multimedia.';

  @override
  String get analyticsTopArtists => 'Artistas principales';

  @override
  String get analyticsTopAuthors => 'Autores principales';

  @override
  String get analyticsTopContributors => 'Colaboradores principales';

  @override
  String analyticsLibrariesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bibliotecas',
      one: '1 biblioteca',
    );
    return '$_temp0';
  }

  @override
  String get analyticsNoIndexedMediaTotals =>
      'Aún no hay totales de contenido indexado para esta selección.';

  @override
  String get analyticsLibraryDetails => 'Detalles de la biblioteca';

  @override
  String get analyticsLibraryBreakdown => 'Desglose de la biblioteca';

  @override
  String get analyticsNoLibrariesAvailable => 'No hay bibliotecas disponibles.';

  @override
  String get analyticsLibraryShare => 'Proporción de elementos por biblioteca';

  @override
  String get analyticsTopRating => 'Clasificación más común';

  @override
  String get analyticsTypicalRuntime => 'Duración típica';

  @override
  String analyticsShareOfItems(String percent) {
    return '$percent% de los elementos';
  }

  @override
  String get adminServerAdministrationTitle => 'Administración del servidor';

  @override
  String get adminServerPathData => 'Datos';

  @override
  String get adminServerPathImageCache => 'Caché de imágenes';

  @override
  String get adminServerPathCache => 'Caché';

  @override
  String get adminServerPathLogs => 'Registros';

  @override
  String get adminServerPathMetadata => 'Metadatos';

  @override
  String get adminServerPathTranscode => 'Transcodificación';

  @override
  String get adminServerPathWeb => 'Web';

  @override
  String get adminNoServerPathsReturned =>
      'Este servidor no ha devuelto ninguna ruta.';

  @override
  String adminPercentUsed(int percent) {
    return '$percent% usado';
  }

  @override
  String get userActivity => 'Actividad de usuarios';

  @override
  String get systemEvents => 'Eventos del sistema';

  @override
  String get needsAttention => 'Necesita atención';

  @override
  String get homeVideos => 'Vídeos caseros';

  @override
  String get mixedContent => 'Contenido mixto';

  @override
  String get homeVideosAndPhotos => 'Vídeos caseros y fotos';

  @override
  String get mixedMoviesAndShows => 'Películas y series mezcladas';

  @override
  String get dolbyVision => 'Dolby Vision';

  @override
  String get noRecordingsFound => 'No se encontraron grabaciones';

  @override
  String noImagePagesFoundInArchive(String extension) {
    return 'No se encontraron páginas de imágenes dentro del archivo .$extension.';
  }

  @override
  String embeddedRendererFailed(int code, String description) {
    return 'Error en el renderizador integrado ($code): $description';
  }

  @override
  String epubRendererFailed(int code, String description) {
    return 'Error en el renderizador de EPUB ($code): $description';
  }

  @override
  String missingLocalFileForReader(String uri) {
    return 'Falta el archivo local para el lector: $uri';
  }

  @override
  String httpStatusWhileOpeningBookData(int status, String uri) {
    return 'HTTP $status al abrir los datos del libro desde $uri';
  }

  @override
  String get noReadableBookEndpointAvailable =>
      'No hay ningún punto de acceso disponible para leer el libro';

  @override
  String unsupportedComicArchiveFormat(String extension) {
    return 'Formato de archivo de cómics no compatible: .$extension';
  }

  @override
  String get cbrExtractionPluginUnavailable =>
      'El complemento de extracción CBR no está disponible en esta plataforma.';

  @override
  String get failedToExtractCbrArchive => 'No se pudo extraer el archivo .cbr.';

  @override
  String get cb7ExtractionUnavailable =>
      'La extracción CB7 no está disponible en esta plataforma.';

  @override
  String get cb7ExtractionPluginUnavailable =>
      'El complemento de extracción CB7 no está disponible en esta plataforma.';

  @override
  String get loadingShuffle => 'Cargando reproducción aleatoria...';

  @override
  String get libraryShuffleLabel => 'ALEATORIO POR BIBLIOTECA';

  @override
  String get randomShuffleLabel => 'ALEATORIO TOTAL';

  @override
  String get genresShuffleLabel => 'ALEATORIO POR GÉNEROS';

  @override
  String get autoHdrSwitching => 'Cambio automático de HDR';

  @override
  String get autoHdrSwitchingDescription =>
      'Activa HDR automáticamente al reproducir vídeo HDR y restaura el modo de pantalla al salir.';

  @override
  String get whenFullscreen => 'En pantalla completa';

  @override
  String get changeArtwork => 'Cambiar la carátula';

  @override
  String get missing => 'Falta';

  @override
  String get clearAllArtworkButton => '¿Borrar todas las carátulas?';

  @override
  String get clearAllArtworkWarning =>
      '¿Seguro que quieres borrar todas las carátulas descargadas?';

  @override
  String get confirmClear => 'Confirmar borrado';

  @override
  String confirmClearMessage(String itemType) {
    return '¿Seguro que quieres borrar $itemType?';
  }

  @override
  String get uploadButton => '¿Subir?';

  @override
  String get resolutionLabel => 'Resolución: ';

  @override
  String get onlyShowInterfaceLanguage =>
      'Mostrar solo las carátulas en el idioma de la interfaz';

  @override
  String get confirmClearAll => 'Confirmar borrado de todo';

  @override
  String get imageUploadSuccess => '¡Imagen subida correctamente!';

  @override
  String imageUploadFailed(String error) {
    return 'Error al subir la imagen: $error';
  }

  @override
  String imageDownloadFailed(String error) {
    return 'Error al establecer la imagen: $error';
  }

  @override
  String imageDeleteFailed(String error) {
    return 'Error al eliminar la imagen: $error';
  }

  @override
  String clearAllArtworkFailed(String error) {
    return 'Error al borrar todas las carátulas: $error';
  }

  @override
  String get yes => 'Sí';

  @override
  String get posterCategory => 'Póster';

  @override
  String get backdropsCategory => 'Imágenes de fondo';

  @override
  String get bannerCategory => 'Banner';

  @override
  String get logoCategory => 'Logo';

  @override
  String get thumbnailCategory => 'Miniatura';

  @override
  String get artCategory => 'Ilustración';

  @override
  String get discArtCategory => 'Ilustración del disco';

  @override
  String get screenshotCategory => 'Captura de pantalla';

  @override
  String get boxCoverCategory => 'Carátula';

  @override
  String get boxRearCoverCategory => 'Contraportada';

  @override
  String get menuArtCategory => 'Ilustración del menú';

  @override
  String get confirmItemPoster => 'el póster';

  @override
  String get confirmItemBackdrop => 'la imagen de fondo';

  @override
  String get confirmItemBanner => 'el banner';

  @override
  String get confirmItemLogo => 'el logo';

  @override
  String get confirmItemThumbnail => 'la miniatura';

  @override
  String get confirmItemArt => 'la ilustración';

  @override
  String get confirmItemDiscArt => 'la ilustración del disco';

  @override
  String get confirmItemScreenshot => 'la captura de pantalla';

  @override
  String get confirmItemBoxCover => 'la carátula';

  @override
  String get confirmItemBoxRearCover => 'la contraportada';

  @override
  String get confirmItemMenuArt => 'la ilustración del menú';

  @override
  String get resolutionAll => 'Todas';

  @override
  String get resolutionHigh => 'Alta (1080p+)';

  @override
  String get resolutionMedium => 'Media (720p)';

  @override
  String get resolutionLow => 'Baja (<720p)';

  @override
  String get sources => 'Fuentes';

  @override
  String get audiobookChapters => 'Capítulos';

  @override
  String get audiobookBookmarks => 'Marcadores';

  @override
  String get audiobookNotes => 'Notas';

  @override
  String get audiobookQueue => 'Cola';

  @override
  String get audiobookTimeline => 'Cronología';

  @override
  String get audiobookTimelineEmpty => 'La cronología está vacía';

  @override
  String get audiobookFocusedTimeline => 'Cronología centrada';

  @override
  String get audiobookFullTimeline => 'Cronología completa';

  @override
  String get audiobookExportBookmarks => 'Exportar marcadores';

  @override
  String get audiobookExportNotes => 'Exportar notas';

  @override
  String get audiobookExportAll => 'Exportar todo';

  @override
  String audiobookExportSuccess(String path) {
    return 'Exportado a $path';
  }

  @override
  String audiobookExportFailed(String error) {
    return 'Error al exportar: $error';
  }

  @override
  String get audiobookLyrics => 'Letra';

  @override
  String get audiobookAddBookmark => 'Añadir marcador';

  @override
  String get audiobookAddNote => 'Añadir nota';

  @override
  String get audiobookEditNote => 'Editar nota';

  @override
  String get audiobookNoteHint => 'Escribe una nota para este momento';

  @override
  String get audiobookSleepTimer => 'Temporizador de apagado';

  @override
  String get audiobookSleepOff => 'Desactivado';

  @override
  String get audiobookSleepEndOfChapter => 'Fin del capítulo';

  @override
  String get audiobookSleepCustom => 'Personalizado';

  @override
  String audiobookSleepRemaining(String remaining) {
    return 'Quedan $remaining';
  }

  @override
  String audiobookSleepMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count min',
      one: '1 min',
    );
    return '$_temp0';
  }

  @override
  String get audiobookPlaybackSpeed => 'Velocidad de reproducción';

  @override
  String get audiobookRemainingTime => 'Restante';

  @override
  String get audiobookElapsedTime => 'Transcurrido';

  @override
  String audiobookSkipBackSeconds(int seconds) {
    return 'Atrás $seconds s';
  }

  @override
  String audiobookSkipForwardSeconds(int seconds) {
    return 'Adelante $seconds s';
  }

  @override
  String get audiobookPreviousChapter => 'Capítulo anterior';

  @override
  String get audiobookNextChapter => 'Capítulo siguiente';

  @override
  String audiobookChapterIndicator(int current, int total) {
    return 'Capítulo $current de $total';
  }

  @override
  String get audiobookNoChapters => 'Sin capítulos';

  @override
  String get audiobookNoBookmarks => 'Aún no hay marcadores';

  @override
  String get audiobookNoNotes => 'Aún no hay notas';

  @override
  String audiobookBookmarkAdded(String position) {
    return 'Marcador añadido en $position';
  }

  @override
  String get audiobookSpeedReset => 'Restablecer a 1.0x';

  @override
  String audiobookSpeedCustomLabel(String value) {
    return '${value}x';
  }

  @override
  String get audiobookSave => 'Guardar';

  @override
  String get audiobookCancel => 'Cancelar';

  @override
  String get audiobookDelete => 'Eliminar';

  @override
  String get subtitlePreferencesDescription =>
      'Cambia los modos de subtítulos, los idiomas predeterminados, la apariencia y las opciones de renderizado.';

  @override
  String get subtitleRendering => 'Renderizado de subtítulos';

  @override
  String get displayOptions => 'Opciones de visualización';

  @override
  String get releaseDateAscending => 'Fecha de estreno (ascendente)';

  @override
  String get releaseDateDescending => 'Fecha de estreno (descendente)';

  @override
  String get libraryWriteAccessWarningTitle =>
      'Aviso de acceso de escritura a la biblioteca';

  @override
  String get libraryWriteAccessHowToFix => 'Cómo solucionarlo:';

  @override
  String get libraryWriteAccessFixSteps =>
      '1. Concede permisos de escritura al usuario del servicio Jellyfin (p. ej., jellyfin o el PUID/PGID de Docker) en las carpetas de tu biblioteca multimedia del servidor.\n\n2. O bien, ve al Panel de control de Jellyfin -> Bibliotecas, edita esta biblioteca y desactiva \'Guardar las carátulas en las carpetas multimedia\' para almacenar las carátulas en la base de datos interna de Jellyfin.';

  @override
  String get dismiss => 'Descartar';

  @override
  String libraryWriteAccessProactiveBody(
    String libraryName,
    String failedPath,
  ) {
    return 'Tu biblioteca \'$libraryName\' está configurada para guardar las carátulas directamente en las carpetas multimedia (la opción \'Guardar las carátulas en las carpetas multimedia\' está activada). Sin embargo, Jellyfin ha comprobado el acceso de escritura y no tiene permiso para escribir archivos en este directorio:\n\n$failedPath';
  }

  @override
  String get libraryWriteAccessReactiveBody =>
      'Parece que Jellyfin no ha podido actualizar la carátula. Tu biblioteca está configurada para guardar las carátulas directamente en las carpetas multimedia (la opción \'Guardar las carátulas en las carpetas multimedia\' está activada). Este error suele producirse cuando el proceso del servidor Jellyfin no tiene permiso para escribir archivos en tus directorios multimedia.';

  @override
  String get replay => 'Volver a reproducir';

  @override
  String get fileInformation => 'Información del archivo';

  @override
  String fileSizeFormat(Object size, Object format) {
    return 'Tamaño: $size  •  Formato: $format';
  }

  @override
  String dateCreatedFormat(Object date) {
    return 'Añadido: $date';
  }

  @override
  String showAllAudioTracks(int count) {
    return 'Mostrar todas las pistas de audio ($count)';
  }

  @override
  String showAllSubtitleTracks(int count) {
    return 'Mostrar todas las pistas de subtítulos ($count)';
  }

  @override
  String get checkingDirectPlay =>
      'Comprobando la compatibilidad con la reproducción directa...';

  @override
  String get directPlayCapabilityLabel =>
      'Compatibilidad con la reproducción directa: ';

  @override
  String get forced => 'Forzado';

  @override
  String get transcodeContainerNotSupported =>
      'El reproductor no admite el formato del contenedor.';

  @override
  String get transcodeVideoCodecNotSupported =>
      'El códec de vídeo no es compatible.';

  @override
  String get transcodeAudioCodecNotSupported =>
      'El códec de audio no es compatible.';

  @override
  String get transcodeSubtitleCodecNotSupported =>
      'El formato de subtítulos no es compatible (requiere incrustarlos).';

  @override
  String get transcodeAudioProfileNotSupported =>
      'El perfil de audio no es compatible.';

  @override
  String get transcodeVideoProfileNotSupported =>
      'El perfil de vídeo no es compatible.';

  @override
  String get transcodeVideoLevelNotSupported =>
      'El nivel de vídeo no es compatible.';

  @override
  String get transcodeVideoResolutionNotSupported =>
      'Este dispositivo no admite la resolución del vídeo.';

  @override
  String get transcodeVideoBitDepthNotSupported =>
      'La profundidad de bits del vídeo no es compatible.';

  @override
  String get transcodeVideoFramerateNotSupported =>
      'La velocidad de fotogramas del vídeo no es compatible.';

  @override
  String get transcodeContainerBitrateExceedsLimit =>
      'La tasa de bits del archivo supera el límite de transmisión del reproductor.';

  @override
  String get transcodeVideoBitrateExceedsLimit =>
      'La tasa de bits del vídeo supera el límite de transmisión.';

  @override
  String get transcodeAudioBitrateExceedsLimit =>
      'La tasa de bits del audio supera el límite de transmisión.';

  @override
  String get transcodeAudioChannelsNotSupported =>
      'El número de canales de audio no es compatible.';

  @override
  String transcodeAudioCodecWithCodec(String codec) {
    return 'El códec de audio ($codec) no es compatible directamente.';
  }

  @override
  String transcodeAudioCodecHintPassthrough(String codec) {
    return 'Consejo: si tu receptor de audio o barra de sonido admite $codec, activa el passthrough de audio en los ajustes de audio.';
  }

  @override
  String transcodeAudioChannelsExceeded(int channels) {
    return 'El número de canales de audio ($channels canales) supera el límite del reproductor.';
  }

  @override
  String get transcodeAudioChannelsHint =>
      'Consejo: ajusta «Canales de audio máximos» o la mezcla multicanal en los ajustes de audio.';

  @override
  String get transcodeSubtitleBurnInAssDisabled =>
      'Los subtítulos ASS/SSA necesitan transcodificación porque la reproducción directa está desactivada.';

  @override
  String get transcodeSubtitleBurnInAssHint =>
      'Consejo: activa «Reproducción directa de ASS/SSA» en los ajustes de reproducción para reproducir sin transcodificar.';

  @override
  String get transcodeSubtitleBurnInPgsDisabled =>
      'Los subtítulos PGS necesitan transcodificación porque la reproducción directa está desactivada.';

  @override
  String get transcodeSubtitleBurnInPgsHint =>
      'Consejo: activa «Reproducción directa de PGS» en los ajustes de reproducción para reproducir sin transcodificar.';

  @override
  String transcodeSubtitleNotSupportedWithCodec(String codec) {
    return 'El formato de subtítulos ($codec) no es compatible directamente y hay que incrustarlo.';
  }

  @override
  String transcodeBitrateExceededWithValues(
    String fileBitrate,
    String maxBitrate,
  ) {
    return 'La tasa de bits del archivo ($fileBitrate) supera el límite de transmisión configurado ($maxBitrate).';
  }

  @override
  String get transcodeBitrateHint =>
      'Consejo: sube la «Tasa de bits máxima» en los ajustes de reproducción para permitir la transmisión directa.';

  @override
  String get transcodeResolutionHint =>
      'Consejo: sube la «Resolución máxima» en los ajustes de reproducción para permitir la transmisión directa.';

  @override
  String get transcodeVideoRangeNotSupported =>
      'Esta pantalla no admite el rango dinámico del vídeo (p. ej., Dolby Vision o HDR).';

  @override
  String get transcodeDolbyVisionProfile7ElDisabled =>
      'La reproducción directa de la capa de mejora de Dolby Vision perfil 7 está desactivada.';

  @override
  String get transcodeDolbyVisionProfile7ElHint =>
      'Consejo: activa «Reproducción directa de Dolby Vision perfil 7» en los ajustes de reproducción si tu pantalla lo admite.';

  @override
  String get transcodeDolbyVisionFallbackPreferenceTranscode =>
      'Según tus ajustes, se prefiere transcodificar como alternativa a Dolby Vision.';

  @override
  String get transcodeDolbyVisionFallbackHint =>
      'Consejo: pon «Alternativa a Dolby Vision» en «Reproducir como HDR10» en los ajustes de reproducción para evitar la transcodificación.';

  @override
  String get transcodeDisplayReportsNoHdr =>
      'La pantalla conectada no indica que admita HDR ni Dolby Vision.';

  @override
  String get transcodeDisplayLacksHdr10ForFallback =>
      'La pantalla conectada no admite HDR10, necesario como alternativa a Dolby Vision.';

  @override
  String get transcodeAudioSampleRateNotSupported =>
      'La frecuencia de muestreo del audio no es compatible.';

  @override
  String get transcodeAudioBitDepthNotSupported =>
      'La profundidad de bits del audio no es compatible.';

  @override
  String get transcodeRefFramesNotSupported =>
      'Los fotogramas de referencia del vídeo superan los límites del reproductor.';

  @override
  String get transcodeAnamorphicVideoNotSupported =>
      'El vídeo anamórfico no es compatible.';

  @override
  String get transcodeInterlacedVideoNotSupported =>
      'El vídeo entrelazado no es compatible.';

  @override
  String get transcodeSecondaryAudioNotSupported =>
      'La pista de audio secundaria necesita transcodificación.';

  @override
  String get transcodeDirectPlayError =>
      'La reproducción directa no es compatible con este formato.';

  @override
  String get sortServerOrder => 'Orden del servidor';

  @override
  String get sortAlphabetical => 'Alfabético';

  @override
  String get sortReleaseAscending => 'Orden de estreno (ascendente)';

  @override
  String get sortReleaseDescending => 'Orden de estreno (descendente)';

  @override
  String get sortCustomDragDrop => 'Personalizado (arrastrar y soltar)';

  @override
  String sortCurrent(String option) {
    return 'Orden: $option';
  }

  @override
  String get playlistSortOptions =>
      'Opciones de orden de la lista de reproducción';

  @override
  String get resetSort => 'Restablecer el orden';

  @override
  String rewatchSeasonEpisode(int season, int episode) {
    return 'Volver a ver T$season:E$episode';
  }

  @override
  String get rewatchPlaylist => 'Volver a ver la lista de reproducción';

  @override
  String get noSubtitlesFound => 'No se han encontrado subtítulos.';

  @override
  String get adminControls => 'Controles de administración';

  @override
  String get impellerRendering => 'Motor de renderizado (Impeller)';

  @override
  String get impellerRenderingSubtitle =>
      'Impeller es el renderizador de GPU moderno de Flutter, que ofrece animaciones más fluidas y menos tirones. En algunos TV box y GPU antiguas puede provocar fallos gráficos o vídeo en negro; desactívalo si te ocurre. Automático elige la mejor opción para tu dispositivo. Reinicia kOS TV para aplicar los cambios.';

  @override
  String get impellerAuto => 'Automático';

  @override
  String get impellerOn => 'Activado';

  @override
  String get impellerOff => 'Desactivado';

  @override
  String get impellerRestartTitle => 'Reinicio necesario';

  @override
  String get impellerRestartMessage =>
      'kOS TV debe reiniciarse para cambiar el motor de renderizado. Cierra la aplicación ahora y vuelve a abrirla para aplicar los cambios.';

  @override
  String get impellerCloseNow => 'Cerrar la aplicación ahora';

  @override
  String get adminRefreshLibrary => 'Actualizar biblioteca';

  @override
  String get adminRefreshAllLibraries => 'Actualizar todas las bibliotecas';

  @override
  String get adminRepoSortDateOldest =>
      'Fecha de adición (más antiguas primero)';

  @override
  String get adminRepoSortDateNewest =>
      'Fecha de adición (más recientes primero)';

  @override
  String get adminRepoSortNameAsc => 'Alfabético (de la A a la Z)';

  @override
  String get adminRepoSortNameDesc => 'Alfabético (de la Z a la A)';

  @override
  String adminAnalyticsLoadingProgress(int percentage) {
    return 'Cargando las analíticas del servidor... $percentage%';
  }

  @override
  String get adminLibChapterImageResolutionMatchSource => 'Igual que el origen';

  @override
  String get imdbTop250Movies => 'Top 250 películas de IMDb';

  @override
  String get imdbTop250TvShows => 'Top 250 series de IMDb';

  @override
  String get imdbMostPopularMovies => 'Películas más populares de IMDb';

  @override
  String get imdbMostPopularTvShows => 'Series más populares de IMDb';

  @override
  String get imdbLowestRatedMovies => 'Películas peor valoradas de IMDb';

  @override
  String get imdbTopEnglishMovies =>
      'Películas en inglés mejor valoradas de IMDb';

  @override
  String get adminSearchParameters => 'Parámetros de búsqueda';

  @override
  String get adminCurrentMetadata => 'Metadatos actuales';

  @override
  String get adminLabelYear => 'Año';

  @override
  String get adminReplaceImages => 'Reemplazar las imágenes existentes';

  @override
  String get adminBackToSearch => 'Volver a los criterios de búsqueda';

  @override
  String get grouping => 'Agrupación';

  @override
  String get groupByType => 'Agrupar por tipo';

  @override
  String get playlistTypes => 'Tipos de lista de reproducción';

  @override
  String get playlistTypeVideo => 'Vídeo';

  @override
  String get playlistTypeMusicVideo => 'Vídeo musical';

  @override
  String get playlistTypeAudio => 'Audio (música)';

  @override
  String get playlistTypeAudiobook => 'Audiolibro';

  @override
  String get playlistTypeBook => 'Libro';

  @override
  String get playlistTypePhoto => 'Foto';

  @override
  String get playlistTypeMixed => 'Mixta';

  @override
  String get videoPlaylistsSection => 'Listas de reproducción de vídeo';

  @override
  String get musicVideoPlaylistsSection =>
      'Listas de reproducción de vídeos musicales';

  @override
  String get audioPlaylistsSection => 'Listas de reproducción de audio';

  @override
  String get audiobookPlaylistsSection =>
      'Listas de reproducción de audiolibros';

  @override
  String get bookPlaylistsSection => 'Listas de reproducción de libros';

  @override
  String get photoPlaylistsSection => 'Listas de reproducción de fotos';

  @override
  String get mixedPlaylistsSection => 'Listas de reproducción mixtas';

  @override
  String get currentTime => 'Hora actual';

  @override
  String get playbackTimeDisplay => 'Tiempo en la barra de progreso';

  @override
  String get settingsPlaybackTimeDisplayDescription =>
      'Elige qué tiempos aparecen alrededor de la barra de progreso de la reproducción.';

  @override
  String get playbackTimeTotal => 'Duración total';

  @override
  String get playbackTimeRemaining => 'Tiempo restante';

  @override
  String get playbackTimeEndsAt => 'Hora de fin';

  @override
  String get playbackTimeElapsed => 'Tiempo transcurrido';

  @override
  String get playbackTimeVideoSection => 'Reproductor de vídeo';

  @override
  String get playbackTimeMusicSection => 'Reproductor de música';

  @override
  String get playbackTimeSlotDescription =>
      'Elige qué se muestra aquí o ocúltalo.';

  @override
  String get playbackTimeAboveBarLeft => 'Encima de la barra, a la izquierda';

  @override
  String get playbackTimeAboveBarCenter => 'Encima de la barra, en el centro';

  @override
  String get playbackTimeAboveBarRight => 'Encima de la barra, a la derecha';

  @override
  String get playbackTimeBelowBarLeft => 'Debajo de la barra, a la izquierda';

  @override
  String get playbackTimeBelowBarCenter => 'Debajo de la barra, en el centro';

  @override
  String get playbackTimeBelowBarRight => 'Debajo de la barra, a la derecha';

  @override
  String get settingsMusicPlaybackTimeDescription =>
      'Elige qué se muestra a la derecha de la barra de progreso de la música.';

  @override
  String get groupByTitle => 'Agrupar por';

  @override
  String get groupByDecade => 'Década (año)';

  @override
  String get groupByParentalRating => 'Clasificación por edades';

  @override
  String get groupByStudio => 'Estudio';

  @override
  String get showAlphabeticalFilters => 'Mostrar alfabeto';

  @override
  String get libraryFolderView => 'Vista de carpetas';

  @override
  String get personalRatingStyle => 'Estilo de valoración personal';

  @override
  String get personalRatingThumbs => 'Me gusta / No me gusta';

  @override
  String get personalRatingStars => '5 estrellas';

  @override
  String get personalRatingNumeric => 'Puntuación sobre 10';

  @override
  String get rate => 'Valorar';

  @override
  String get like => 'Me gusta';

  @override
  String get dislike => 'No me gusta';

  @override
  String get personalRatingClear => 'Quitar valoración';

  @override
  String get personalRatingRated => 'Valorado';

  @override
  String get personalRatingMine => 'Mi valoración';

  @override
  String get personalRatingSaveFailed => 'No se pudo guardar la valoración';

  @override
  String get increase => 'Aumentar';

  @override
  String get decrease => 'Disminuir';

  @override
  String personalRatingOutOfTen(String rating) {
    return '$rating / 10';
  }

  @override
  String personalRatingOutOfFive(String rating) {
    return '$rating / 5';
  }

  @override
  String get filterInProgress => 'En curso';

  @override
  String get filterUnreleased => 'Sin estrenar';

  @override
  String get filterTrailers => 'Tráileres';

  @override
  String get filterExtras => 'Extras';

  @override
  String get filterThemeSongs => 'Canciones de tema';

  @override
  String get filterThemeVideos => 'Vídeos de tema';

  @override
  String get source => 'Origen';

  @override
  String get years => 'Años';

  @override
  String get audioLanguage => 'Idioma del audio';

  @override
  String get subtitleLanguage => 'Idioma de los subtítulos';

  @override
  String get clearFilters => 'Quitar filtros';

  @override
  String get subtitleHdrSeparate => 'Estilo aparte para HDR';

  @override
  String get subtitleHdrSeparateSubtitle =>
      'El blanco brilla mucho más en HDR que en SDR, así que un estilo más tenue aquí evita que deslumbre';

  @override
  String get subtitleBold => 'Texto en negrita';

  @override
  String get subtitleStrokeWidth => 'Grosor del contorno del texto';

  @override
  String get subtitleFont => 'Fuente';

  @override
  String get subtitleFontDescription =>
      'Las fuentes se descargan de Google Fonts la primera vez que las eliges';

  @override
  String subtitleFontDownloadFailed(String font) {
    return 'No se pudo descargar $font';
  }

  @override
  String get subtitleShadow => 'Sombra del texto';

  @override
  String get subtitleShadowIntensity => 'Intensidad de la sombra';

  @override
  String get subtitleShadowOffset => 'Desplazamiento de la sombra';

  @override
  String get subtitleShadowBlur => 'Desenfoque de la sombra';

  @override
  String get scrollSensitivity => 'Sensibilidad del desplazamiento';

  @override
  String get scrollSensitivitySubtitle =>
      'Cuánto se desplaza cada paso de la rueda del ratón';

  @override
  String get mediaDetailsAndSpoilers => 'Detalles del contenido y spoilers';

  @override
  String get openTrailersExternally => 'Abrir tráileres en una app externa';

  @override
  String get openTrailersExternallySubtitle =>
      'Los tráileres se abren en la app de YouTube o en el navegador en vez de en el reproductor integrado';

  @override
  String get hideDetailsMediaDescription => 'Ocultar la descripción';

  @override
  String get hideDetailsMediaDescriptionSubtitle =>
      'Oculta el texto descriptivo de la película o el episodio.';

  @override
  String get detailUseSeriesThumbnails => 'Usar miniaturas de la serie';

  @override
  String get detailUseSeriesThumbnailsSubtitle =>
      'Sustituye todas las miniaturas de la página de detalles de estilo Clásico por la miniatura de la serie';

  @override
  String get hideHomeMediaDescription => 'Ocultar la descripción';

  @override
  String get hideHomeMediaDescriptionSubtitle =>
      'Oculta el texto descriptivo de la película o el episodio.';

  @override
  String get hideHomeWatchProgress => 'Ocultar el progreso';

  @override
  String get hideHomeWatchProgressSubtitle =>
      'Oculta la barra de progreso en los pósteres de lo que has empezado a ver.';

  @override
  String get hideHomeUnwatchedCount => 'Ocultar el contador de no vistos';

  @override
  String get hideHomeUnwatchedCountSubtitle =>
      'Oculta la insignia que indica cuántos episodios te quedan por ver.';

  @override
  String get continueWatchingAndNextUpHeader =>
      'Continuar viendo y A continuación';

  @override
  String get setupSkip => 'Saltar la configuración';

  @override
  String get setupNavbarQuestion => '¿Dónde quieres la navegación?';

  @override
  String get setupMediaBarQuestion =>
      '¿Cómo quieres que se vea la parte de arriba de Inicio?';

  @override
  String get setupHomeRowsQuestion => '¿Cómo quieres que se vean las filas?';

  @override
  String get setupDetailQuestion =>
      '¿Cómo quieres que se vea una película o serie al abrirla?';

  @override
  String get setupTourQuestion =>
      'Ya está todo. Esto es lo demás que puedes encontrar.';

  @override
  String get setupPlaybackLanguages => 'Idiomas de reproducción';

  @override
  String get setupOptional => 'Opcional';

  @override
  String get setupStyleClassic => 'Clásico';

  @override
  String get setupStyleModern => 'Moderno';

  @override
  String get setupRowsClassicHint =>
      'Compacto. Más filas en pantalla a la vez.';

  @override
  String get setupRowsModernHint =>
      'Tarjetas más grandes con el título debajo.';

  @override
  String get setupDetailClassicHint => 'Todo centrado en una sola columna.';

  @override
  String get setupDetailModernHint =>
      'Cinematográfico, con pestañas para el reparto y los extras.';

  @override
  String get setupStyleSpotlight => 'Foco';

  @override
  String get setupDetailSpotlightHint =>
      'La imagen principal primero, con tarjetas emergentes para el reparto y los extras.';

  @override
  String get setupStyleNouveau => 'Nuevo';

  @override
  String get setupDetailNouveauHint =>
      'A pantalla completa, con las secciones apiladas en vez de en pestañas.';

  @override
  String get setupStyleMinimalist => 'Minimalista';

  @override
  String get setupDetailMinimalistHint =>
      'Las imágenes, un botón de reproducir y los episodios.';

  @override
  String get setupStyleStage => 'Escenario';

  @override
  String get setupDetailStageHint =>
      'El póster delante, con el botón de reproducir debajo y los detalles al lado.';

  @override
  String get setupStylePremiere => 'Estreno';

  @override
  String get setupDetailPremiereHint =>
      'El título centrado sobre un fondo a pantalla completa, y todo lo demás más abajo.';

  @override
  String get setupStyleQuickLook => 'Vistazo rápido';

  @override
  String get setupDetailQuickLookHint =>
      'Un panel sobre la pantalla en la que estabas, con el botón de reproducir y lo básico, y la página completa a una pulsación.';

  @override
  String get setupStyleFrost => 'Escarcha';

  @override
  String get setupDetailFrostHint =>
      'El título en una ventana de cristal sobre su imagen desenfocada, con pestañas bajo los botones.';

  @override
  String get setupNavbarStyleQuestion => '¿Cómo quieres la barra inferior?';

  @override
  String get setupNavbarStyleDockHint =>
      'Una cápsula flotante con etiquetas bajo cada pestaña.';

  @override
  String get setupNavbarStyleSplitHint =>
      'Buscar tiene su propio botón y la barra se encoge mientras te desplazas.';

  @override
  String get setupNavbarStyleStripHint =>
      'Una barra a todo lo ancho del borde inferior.';

  @override
  String get setupPickALook => 'Elige un aspecto';

  @override
  String get setupTourMoreHeader => 'Hay más esperándote en Ajustes';

  @override
  String get setupTourBulletSyncPlay => 'Ver juntos con SyncPlay';

  @override
  String get setupTourBulletThemes => 'Temas personalizados';

  @override
  String get setupTourBulletDownloads => 'Descargas sin conexión';

  @override
  String get setupTourBulletMore => 'Y mucho más';

  @override
  String setupStepOf(int current, int total) {
    return 'Paso $current de $total';
  }

  @override
  String get setupCurrent => 'Actual';

  @override
  String get setupMoonbaseTitle =>
      'Añade el complemento de kOS TV a tu servidor';

  @override
  String get setupMoonbaseHint =>
      'Un complemento gratuito para el servidor que desbloquea más funciones de kOS TV';

  @override
  String get setupMoonbaseIntro =>
      'El complemento es gratuito y funciona en tu servidor. Con él, kOS TV tiene:';

  @override
  String get setupMoonbaseAskAdmin =>
      'Solo un administrador del servidor puede instalarlo. Envíale este enlace.';

  @override
  String get setupMoonbaseManualSteps =>
      'Instalarlo en tu servidor lleva unos cuantos pasos. Están todos en este enlace.';

  @override
  String get setupMoonbaseInstalling =>
      'Instalando el complemento del servidor...';

  @override
  String get setupMoonbaseInstalled =>
      'El complemento del servidor está instalado. Se activa cuando el servidor se reinicia, y eso detiene lo que se esté reproduciendo ahora.';

  @override
  String get setupMoonbaseRestarting =>
      'El servidor se está reiniciando. El complemento se activará cuando vuelva.';

  @override
  String get moonbaseFeatureSync =>
      'Ajustes sincronizados entre tus dispositivos';

  @override
  String get moonbaseFeatureRatings => 'Más valoraciones y reseñas de TMDB';

  @override
  String get moonbaseFeatureRows =>
      'Filas personalizadas con tus listas favoritas';

  @override
  String get moonbaseFeatureGames =>
      'Juegos retro con partidas guardadas sincronizadas';

  @override
  String get moonbaseFeatureCalendar =>
      'Un calendario con lo que está por llegar';

  @override
  String get moonbaseFeatureCollections =>
      'Tu propio orden para cada colección';

  @override
  String get moonbaseFeatureMessages =>
      'Mensajes del administrador de tu servidor';

  @override
  String setupMoonbaseInstallFailed(String error) {
    return 'No se pudo instalar el complemento del servidor. $error';
  }

  @override
  String get setupTvHint =>
      'Arriba y abajo para previsualizar · OK para elegir · Atrás dos veces para saltar';

  @override
  String get setupNavbarTopHint =>
      'Pestañas en la parte de arriba de la pantalla.';

  @override
  String get setupNavbarLeftHint =>
      'Una barra estrecha de iconos en el lado izquierdo.';

  @override
  String get setupNavbarBottomHint =>
      'Pestañas en el borde inferior, al alcance del pulgar.';

  @override
  String get setupMediaBarMoonfinHint =>
      'Imágenes grandes con el título, los detalles y la sinopsis encima.';

  @override
  String get setupMediaBarMakdHint =>
      'Imágenes grandes encabezadas por el logotipo del título en grande.';

  @override
  String get setupMediaBarBookshelfHint =>
      'Títulos colocados como lomos de libros en una estantería, con el destacado de frente.';

  @override
  String get setupMediaBarGalleryHint =>
      'El título destacado abierto, con los siguientes en fila a su lado.';

  @override
  String get setupMediaBarBannerHint =>
      'Una franja más baja encima de tus filas, para que quepan más en pantalla.';

  @override
  String get setupMediaBarAyaHint =>
      'Primero las imágenes, en un panel enmarcado, con tus filas justo debajo.';

  @override
  String get setupMediaBarOffHint =>
      'Sin zona destacada. Inicio se abre directamente en tus filas.';

  @override
  String get runSetupAgain => 'Repetir la configuración inicial';

  @override
  String get serverMessages => 'Mensajes';

  @override
  String get serverMessagesEmpty => 'Aún no hay mensajes de tu servidor';

  @override
  String get serverMessagesMarkAllRead => 'Marcar todo como leído';

  @override
  String get serverMessagesShowButton => 'Mostrar el botón de mensajes';

  @override
  String get serverMessagesShowButtonSubtitle =>
      'Añade al menú un botón para los mensajes que envía el administrador de tu servidor';

  @override
  String get showBookDiscoverTab =>
      'Mostrar Descubrir de Open Library en las bibliotecas de libros';

  @override
  String get showBookDiscoverTabDescription =>
      'Explora títulos de Open Library y LibriVox en tus bibliotecas de libros y audiolibros';

  @override
  String get bookFoldersAsSeries => 'Tratar las carpetas de libros como series';

  @override
  String get bookFoldersAsSeriesDescription =>
      'Trata las carpetas con libros como series en lugar de basarse en los metadatos de cada libro';

  @override
  String get autoDownloadNewEpisodes =>
      'Descargar automáticamente los episodios nuevos';

  @override
  String get autoDownloadStop => 'Dejar de descargar automáticamente';

  @override
  String autoDownloadKeepUnwatchedSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Descarga los episodios nuevos, con $count sin ver como máximo a la vez',
      one: 'Descarga los episodios nuevos, con 1 sin ver como máximo a la vez',
      zero: 'Descarga todos los episodios nuevos',
    );
    return '$_temp0';
  }

  @override
  String autoDownloadStopSubtitle(String quality) {
    return 'Activada • $quality';
  }

  @override
  String get autoDownloadTranscodedForegroundNote =>
      'Las calidades transcodificadas solo se descargan con kOS TV abierto. La calidad original también se descarga en segundo plano.';

  @override
  String get autoDownloadTranscodedRunningNote =>
      'Las descargas transcodificadas no se pueden reanudar tras una interrupción y vuelven a empezar desde el principio. La calidad original sí se puede reanudar.';

  @override
  String get autoDownloadForegroundOnly => 'Solo descarga con kOS TV abierto';

  @override
  String get autoDownloadQualityTitle => 'Calidad de la descarga automática';

  @override
  String autoDownloadEnabledFor(String title) {
    return 'Descarga automática activada para $title';
  }

  @override
  String autoDownloadStoppedFor(String title) {
    return 'Descarga automática desactivada para $title';
  }

  @override
  String get smartDownloadsSection => 'Descargas inteligentes';

  @override
  String get smartDownloadsEnable => 'Descargar los siguientes episodios';

  @override
  String get smartDownloadsEnableDescription =>
      'Cuando terminas un episodio en cualquier dispositivo, kOS TV descarga los siguientes. Los episodios que descarga se borran cuando los ves.';

  @override
  String get smartDownloadsKeepReady => 'Episodios que mantener descargados';

  @override
  String smartDownloadsKeepReadySubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Mantiene descargados los $count episodios siguientes',
      one: 'Mantiene descargado el siguiente episodio',
    );
    return '$_temp0';
  }

  @override
  String get smartDownloadsKeepReadyLowered =>
      'Los episodios ya descargados se quedan en tu dispositivo. El nuevo número se aplica a las próximas descargas.';

  @override
  String get autoDownloadSection => 'Descargas automáticas';

  @override
  String get autoDownloadEnable => 'Activar las descargas automáticas';

  @override
  String get autoDownloadEnableSubtitle =>
      'Descarga los episodios nuevos de las series que sigues. Los episodios que ya hay se pueden seguir descargando a mano.';

  @override
  String get autoDownloadKeepUnwatched => 'Episodios sin ver que mantener';

  @override
  String get autoDownloadKeepAll => 'Todos';

  @override
  String get autoDownloadDelete => 'Borrar episodios descargados';

  @override
  String get autoDownloadDeleteFollowedSubtitle =>
      'Cuándo quitar los episodios descargados de las series que sigues, después de verlos';

  @override
  String get removeWatchedDownloads => 'Quitar descargas vistas';

  @override
  String get removeWatchedDownloadsSubtitle =>
      'Cuándo quitar los episodios y películas que has descargado tú. Solo se quitan los que veas después de activar esto';

  @override
  String get removeWatchedAsk => 'Preguntarme';

  @override
  String get deleteFinishedDownloadTitle => '¿Borrar esta descarga?';

  @override
  String deleteFinishedDownloadMessage(String title) {
    return 'Has terminado $title. Borra su descarga para liberar espacio, o consérvala y no volveremos a preguntarte.';
  }

  @override
  String get notNow => 'Ahora no';

  @override
  String get keepDownloaded => 'Mantener descargado';

  @override
  String get keepDownloadedSubtitle =>
      'No quitarlo nunca automáticamente después de verlo';

  @override
  String get autoDownloadDeleteNever => 'Nunca';

  @override
  String get autoDownloadDeleteImmediately => 'Justo después de verlo';

  @override
  String get autoDownloadDeleteAfterDay => '1 día después de verlo';

  @override
  String get autoDownloadDeleteAfterWeek => '1 semana después de verlo';

  @override
  String get autoDownloadBackgroundRefresh => 'Comprobar en segundo plano';

  @override
  String get autoDownloadBackgroundRefreshSubtitle =>
      'Permite que el sistema busque episodios nuevos de vez en cuando con kOS TV cerrado';

  @override
  String get autoDownloadBackgroundRefreshDenied =>
      'La actualización en segundo plano está desactivada para kOS TV. Actívala en los Ajustes de iOS.';

  @override
  String get autoDownloadBackgroundRestrictedAndroid =>
      'El uso en segundo plano de kOS TV está restringido en los Ajustes de Android.';

  @override
  String get autoDownloadCheckNow => 'Comprobar ahora';

  @override
  String get autoDownloadChecking => 'Comprobando...';

  @override
  String get autoDownloadNeverChecked => 'Aún no se ha comprobado';

  @override
  String autoDownloadLastCheck(String when, int queued) {
    String _temp0 = intl.Intl.pluralLogic(
      queued,
      locale: localeName,
      other: '$queued episodios en cola',
      one: '1 episodio en cola',
      zero: 'nada nuevo',
    );
    return 'Última comprobación $when: $_temp0';
  }

  @override
  String autoDownloadLastCheckFailed(String when, String error) {
    return 'La última comprobación $when falló: $error';
  }

  @override
  String get autoDownloadFollowedSeries => 'Series que sigues';

  @override
  String get autoDownloadNoSubscriptions =>
      'Abre una serie y elige «Descargar automáticamente los episodios nuevos» en su menú de descarga';

  @override
  String get autoDownloadRemove => 'Dejar de seguir';

  @override
  String get autoDownloadStorageFull => 'No hay espacio suficiente';

  @override
  String get autoDownloadWaitingForWifi => 'Esperando WiFi';

  @override
  String get downloadNotificationRunning => 'Descargando';

  @override
  String downloadNotificationRunningBatch(int done, int total) {
    return 'Descargando ($done/$total)';
  }

  @override
  String downloadNotificationProgress(String name, int percent) {
    return '$name — $percent%';
  }

  @override
  String downloadNotificationTransfer(
    String name,
    String progress,
    String timeRemaining,
  ) {
    return '$name — $progress · $timeRemaining';
  }

  @override
  String downloadNotificationStarting(String name) {
    return '$name...';
  }

  @override
  String downloadNotificationCompleteTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Descargas completadas',
      one: 'Descarga completada',
    );
    return '$_temp0';
  }

  @override
  String downloadNotificationSaved(String name) {
    return '$name disponible sin conexión';
  }

  @override
  String downloadNotificationSavedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos disponibles sin conexión',
      one: '1 elemento disponible sin conexión',
    );
    return '$_temp0';
  }

  @override
  String downloadNotificationSeriesEpisodes(String series, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodios',
      one: '1 episodio',
    );
    return '$series: $_temp0';
  }

  @override
  String get downloadNotificationFailedTitle => 'Error en la descarga';

  @override
  String downloadNotificationFailedBody(String name, String error) {
    return '$name: $error';
  }

  @override
  String get serverMessagesNotificationTitle => 'Mensaje del servidor';

  @override
  String get serverMessagesNotificationReceived => 'Mensaje recibido';

  @override
  String get downloadStorageLimitReached =>
      'Se ha alcanzado el límite de almacenamiento. Libera espacio o aumenta el límite.';

  @override
  String downloadNotEnoughStorage(String needed, String free) {
    return 'No hay espacio suficiente: se necesitan $needed y quedan $free libres';
  }

  @override
  String get autoDownloadStorageFullTitle =>
      'No hay espacio para los episodios nuevos';

  @override
  String autoDownloadStorageFullBody(int count, String name, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hay $count episodios esperando espacio.',
      one: '$name necesita $size.',
    );
    return '$_temp0 Libera espacio o sube el límite de descargas.';
  }

  @override
  String get pageTransitions => 'Transiciones de página';

  @override
  String get pageTransitionsSubtitle =>
      'Ajusta la duración del fundido al cambiar de página';

  @override
  String get navigationSpeed => 'Velocidad de navegación';

  @override
  String get navigationSpeedSubtitle =>
      'Ajusta lo rápido que se mueve el indicador de foco entre elementos y filas';

  @override
  String get modernCardsTransitionSpeed =>
      'Velocidad de transición de las tarjetas modernas';

  @override
  String get modernCardsTransitionSpeedSubtitle =>
      'Ajusta la velocidad de la animación al ampliar la tarjeta moderna enfocada';

  @override
  String get delayCardExpansionOnRapidScroll =>
      'Retrasar la ampliación de tarjetas al desplazarte rápido';

  @override
  String get delayCardExpansionOnRapidScrollSubtitle =>
      'Espera a que el foco se detenga antes de ampliar las tarjetas modernas';

  @override
  String get animationSpeedExtraSlow => 'Muy lenta';

  @override
  String get animationSpeedSlow => 'Lenta';

  @override
  String get animationSpeedMedium => 'Media';

  @override
  String get animationSpeedFast => 'Rápida';

  @override
  String get animationSpeedOff => 'Desactivada';

  @override
  String get pageTransitionFadeNone => 'Sin fundido';

  @override
  String get pageTransitionFadeShort => 'Fundido corto';

  @override
  String get pageTransitionFadeMedium => 'Fundido medio';

  @override
  String get pageTransitionFadeLong => 'Fundido largo';

  @override
  String get siriRemoteSwipeSensitivity =>
      'Sensibilidad del deslizamiento en el panel táctil';

  @override
  String get siriRemoteSwipeSensitivityDescription =>
      'Cuánto se mueve el foco con cada deslizamiento en el panel táctil del Siri Remote';

  @override
  String get appleTvHomeScreen => 'Pantalla de inicio del Apple TV';

  @override
  String get topShelf => 'Top Shelf';

  @override
  String get topShelfDescription =>
      'Lo que muestra la pantalla de inicio del Apple TV encima del icono de kOS TV cuando está seleccionado. Este ajuste solo se aplica a este dispositivo.';

  @override
  String get topShelfLatestMedia => 'Contenido reciente';

  @override
  String get topShelfAppBanner => 'Banner de kOS TV';

  @override
  String get keepVideoClearOfDynamicIsland =>
      'Apartar el vídeo de la Dynamic Island';

  @override
  String get keepVideoClearOfDynamicIslandDescription =>
      'En horizontal, la cámara tapa un borde de la pantalla. Esto aparta la imagen de esa zona, y solo cambia algo en los vídeos lo bastante anchos para llegar hasta allí.';

  @override
  String get bottomNavbarStyle => 'Estilo de la barra inferior';

  @override
  String get bottomNavbarStyleDock => 'Dock';

  @override
  String get bottomNavbarStyleSplit => 'Dividida';

  @override
  String get bottomNavbarStyleStrip => 'Franja';

  @override
  String get bottomNavbarTabs => 'Pestañas de la barra inferior';

  @override
  String get bottomNavbarTabsDescription =>
      'Fija hasta 3 pestañas entre Inicio y Tú. Todo lo demás está en el panel de la barra inferior.';

  @override
  String get bottomNavbarTabsAutomatic => 'Automático';

  @override
  String get bottomNavbarTabsPinned => 'Fijadas';

  @override
  String get bottomNavbarTabsAvailable => 'Disponibles';

  @override
  String get bottomNavbarTabsReset => 'Volver a automático';

  @override
  String get bottomNavbarTabsLimit =>
      'Puedes fijar hasta 3 pestañas. Quita una para fijar otra.';

  @override
  String get bottomNavbarTabTurnedOff => 'Desactivada en Botones';

  @override
  String get bottomNavbarSplitSearchNote =>
      'Con el estilo Dividida, Buscar siempre tiene su propio botón.';

  @override
  String get bottomNavbarButtonsNote =>
      'Estos botones deciden qué aparece en el panel de la barra inferior y qué pestañas puedes fijar en ella. Las pestañas que ya están en la barra no aparecen aquí.';

  @override
  String get navYou => 'Tú';

  @override
  String get cinemaSkipPrerolls => 'Botón Saltar en el modo cine';

  @override
  String get cinemaSkipPrerollsDescription =>
      'Muestra un botón Saltar durante los tráileres, anuncios y otros vídeos previos del modo cine.';

  @override
  String get detailsPage => 'Página de detalles';

  @override
  String get storageAndDownloads => 'Almacenamiento y descargas';

  @override
  String get settingsSync => 'Sincronización de ajustes';

  @override
  String get settingsSyncSubtitle =>
      'Sincronización con el complemento del servidor y perfiles de personalización';

  @override
  String get navigationBar => 'Barra de navegación';

  @override
  String get homeRows => 'Filas';

  @override
  String get homeRowsSubtitle => 'Activa o desactiva filas y cambia su orden';

  @override
  String get rowOptions => 'Opciones de las filas';

  @override
  String get rowOptionsSubtitle => 'Orden y contenido de cada fila';

  @override
  String get imageTypePerRow => 'Tipo de imagen por fila';

  @override
  String get externalSources => 'Fuentes externas';

  @override
  String get qualityAndDecoding => 'Calidad y decodificación';

  @override
  String get qualityAndDecodingSubtitle =>
      'Tasa de bits, resolución, decodificación, HDR y Dolby Vision';

  @override
  String get skippingAndAutoplay => 'Saltos y reproducción automática';

  @override
  String get advancedPlayback => 'Reproducción avanzada';

  @override
  String get advancedPlaybackSubtitle =>
      'Elección de reproductor, reproductores externos y mpv';

  @override
  String get settingsAccountSubtitle =>
      'Inicio de sesión, código PIN, modo infantil, control parental y sincronización de ajustes';

  @override
  String get settingsGeneralSubtitle => 'Idioma, reloj, entrada y rendimiento';

  @override
  String get settingsAppearanceSubtitle =>
      'Navegación, pantalla de inicio, bibliotecas, página de detalles y temas';

  @override
  String get settingsHomeScreenSubtitle =>
      'Filas, barra multimedia, aspecto y fuentes externas';

  @override
  String get settingsLibrariesEntrySubtitle =>
      'Visibilidad y orden de las bibliotecas, y páginas de biblioteca';

  @override
  String get settingsDetailsPageSubtitle =>
      'Diseño, botones, secciones, valoraciones y música de tema';

  @override
  String get settingsPlaybackSubtitle =>
      'Reproductor, calidad, audio, subtítulos, saltos y Ver juntos';

  @override
  String get settingsStorageSubtitle =>
      'Descargas, ubicación del almacenamiento y caché de imágenes';

  @override
  String get settingsSignInSection => 'Inicio de sesión';

  @override
  String get settingsFamilySection => 'Familia';

  @override
  String get settingsServersSection => 'Servidores';

  @override
  String get settingsLanguageSection => 'Idioma';

  @override
  String get settingsInputSection => 'Entrada';

  @override
  String get settingsMotionSection => 'Animaciones';

  @override
  String get settingsContentsSection => 'Contenido';

  @override
  String get settingsLooksSection => 'Aspecto';

  @override
  String get settingsAudioAndSubtitlesSection => 'Audio y subtítulos';

  @override
  String get settingsSkippingAndQueueSection => 'Saltos y cola';

  @override
  String get settingsWatchTogetherSection => 'Ver juntos';

  @override
  String get settingsAdvancedSection => 'Avanzado';

  @override
  String get playerSettingsSubtitle =>
      'Controles, avance y retroceso, botones del reproductor y Trickplay';

  @override
  String get siloPasswordChangeTitle => 'Elige una contraseña nueva';

  @override
  String get siloPasswordChangeMessage =>
      'Esta cuenta tiene una contraseña temporal. Elige una nueva para terminar de iniciar sesión.';

  @override
  String get siloPasswordChangeNew => 'Contraseña nueva';

  @override
  String get siloPasswordChangeConfirm => 'Confirma la contraseña nueva';

  @override
  String get siloPasswordChangeSubmit => 'Cambiar contraseña';

  @override
  String siloPasswordChangeTooShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Usa al menos $count caracteres',
      one: 'Usa al menos 1 carácter',
    );
    return '$_temp0';
  }

  @override
  String get siloPasswordChangeTooLong => 'La contraseña es demasiado larga';

  @override
  String get siloPasswordChangeMismatch => 'Las contraseñas no coinciden';

  @override
  String get siloPasswordChangeSameAsTemporary =>
      'Elige una contraseña distinta de la temporal';

  @override
  String get siloPasswordChangeFailed =>
      'No se pudo cambiar la contraseña. Inténtalo de nuevo.';

  @override
  String get siloPasswordChangeUnavailable =>
      'Esta cuenta tiene una contraseña temporal y este servidor no permite cambiarla aquí. Cámbiala en la app web de Silo y vuelve a iniciar sesión.';

  @override
  String get siloPasswordChangedSignInAgain =>
      'Se ha cambiado tu contraseña. Inicia sesión con la contraseña nueva.';

  @override
  String get siloServerRowSubtitle => 'De tu servidor';

  @override
  String get playlistSortReleaseDate => 'Fecha de estreno';

  @override
  String get playlistSortCriticRating => 'Valoración de la crítica';

  @override
  String get playlistSortRuntime => 'Duración';

  @override
  String get playlistSortLastPlayed => 'Última reproducción';

  @override
  String get playlistSortPlayCount => 'Número de reproducciones';

  @override
  String get playlistSortRandom => 'Aleatorio';

  @override
  String playlistFilterActiveCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count activos',
      one: '1 activo',
    );
    return '$_temp0';
  }

  @override
  String get playlistNoMatchingTracks =>
      'Ninguna pista coincide con los filtros activos';

  @override
  String get librarySortPlaylistOrder => 'Orden de la lista';

  @override
  String get librarySortDateAdded => 'Fecha de incorporación';

  @override
  String get librarySortDateEpisodeAdded => 'Fecha del último episodio';

  @override
  String get librarySortParentalRating => 'Clasificación por edades';

  @override
  String get librarySortMyRating => 'Mi valoración';

  @override
  String get librarySortAlbumArtist => 'Artista del álbum';

  @override
  String get librarySortAlbum => 'Álbum';

  @override
  String get librarySortArtist => 'Artista';

  @override
  String get librarySortTrackNumber => 'Número de pista';

  @override
  String get librarySortGenre => 'Género';

  @override
  String get librarySortFoldersFirst => 'Carpetas primero';

  @override
  String get librarySortLength => 'Duración';

  @override
  String get homeScreenBackdrop => 'Fondo de la pantalla de inicio';

  @override
  String get homeScreenBackdropFullScreen => 'Pantalla completa';

  @override
  String get homeScreenBackdropCorner => 'Esquina';

  @override
  String get homeScreenBackdropTop => 'Arriba';

  @override
  String get detailsScreenBackdrop => 'Fondo de la pantalla de detalles';

  @override
  String get detailsBackdropSize => 'Tamaño del fondo';

  @override
  String get detailsBackdropFullScreen => 'Pantalla completa';

  @override
  String get detailsBackdropFit => 'Ajustado';

  @override
  String get libraryBackdrops => 'Fondos de las bibliotecas';

  @override
  String get playbackInfoChannel => 'Canal';

  @override
  String get playbackInfoProgram => 'Programa';

  @override
  String get playbackInfoWhy => 'Motivo';

  @override
  String get playbackInfoServerCompatibilityCheck =>
      'Comprobación de compatibilidad del servidor';

  @override
  String get playbackInfoBitrateUnavailable => 'Tasa de bits no disponible';

  @override
  String get playbackInfoQualityLimit => 'Límite de calidad';

  @override
  String get playbackInfoFrameRate => 'Velocidad de fotogramas';

  @override
  String get playbackInfoDelivery => 'Entrega';

  @override
  String get playbackInfoFile => 'Archivo';

  @override
  String get playbackInfoTechnical => 'Técnico';

  @override
  String get playbackInfoDevice => 'Dispositivo';

  @override
  String get playbackInfoAudioRoute => 'Ruta del audio';

  @override
  String get playbackInfoSurround51 => 'Envolvente 5.1';

  @override
  String get playbackInfoSurround71 => 'Envolvente 7.1';

  @override
  String playbackInfoChannelCount(int count) {
    return '$count canales';
  }

  @override
  String get playbackInfoBurnedIn => 'Grabados en la imagen por el servidor';

  @override
  String playbackInfoOriginal(String value, String original) {
    return '$value (original $original)';
  }

  @override
  String playbackInfoConvertedFrom(String value, String source) {
    return '$value (convertido de $source)';
  }

  @override
  String playbackInfoResolutionConverted(
    String name,
    String size,
    String source,
  ) {
    return '$name ($size, convertido de $source)';
  }

  @override
  String get playbackInfoNoteDirectPlay =>
      'Se reproduce el archivo original tal cual.';

  @override
  String get playbackInfoNoteDirectStream =>
      'El servidor está reempaquetando el archivo sin convertirlo.';

  @override
  String get playbackInfoNoteLiveRelay =>
      'El servidor está retransmitiendo el canal sin convertirlo.';

  @override
  String playbackInfoFrameRateFrom(String rate, String source) {
    return '$rate fps ($source)';
  }

  @override
  String get playbackInfoRateSourceHeader => 'cabecera del vídeo';

  @override
  String get playbackInfoRateSourceMeasured => 'medido';

  @override
  String get playbackInfoRateSourceServer => 'servidor';

  @override
  String get playbackInfoServerFrameRate =>
      'Velocidad de fotogramas del servidor';

  @override
  String get playbackInfoScan => 'Barrido';

  @override
  String get playbackInfoProgressive => 'Progresivo';

  @override
  String get playbackInfoInterlaced => 'Entrelazado';

  @override
  String get playbackInfoRepeatedFields => 'Telecine (campos repetidos)';

  @override
  String get playbackInfoHdmiOutput => 'Salida HDMI';

  @override
  String playbackInfoDisplayMode(String width, String height, String rate) {
    return '$width×$height @ $rate Hz';
  }

  @override
  String get playbackInfoRateCorrections => 'Correcciones de frecuencia';

  @override
  String get playbackInfoAudioOutput => 'Salida';

  @override
  String playbackInfoPassthroughOf(String codec) {
    return 'Passthrough ($codec)';
  }

  @override
  String playbackInfoDecodedTo(String channels) {
    return 'Decodificado ($channels)';
  }

  @override
  String get playbackInfoNoteTranscodeVideo =>
      'El servidor está convirtiendo el vídeo para que este dispositivo pueda reproducirlo.';

  @override
  String get playbackInfoNoteTranscodeAudio =>
      'El servidor está convirtiendo el audio para que este dispositivo pueda reproducirlo.';

  @override
  String get playbackInfoNoteTranscodeBoth =>
      'El servidor está convirtiendo el vídeo y el audio para que este dispositivo pueda reproducirlos.';

  @override
  String get playbackInfoNoteTranscodeUnknown =>
      'El servidor está convirtiendo este archivo para que este dispositivo pueda reproducirlo.';

  @override
  String get playbackInfoNoteOffline =>
      'Se está reproduciendo una copia descargada.';

  @override
  String get playbackInfoWhyForced =>
      'La transcodificación está forzada en los ajustes';

  @override
  String get playbackInfoWhyBitrate =>
      'La tasa de bits supera el límite de streaming';

  @override
  String get playbackInfoWhyContainer =>
      'Este dispositivo no puede reproducir este tipo de archivo';

  @override
  String get playbackInfoWhyVideo =>
      'Este dispositivo no puede reproducir este formato de vídeo';

  @override
  String get playbackInfoWhyHdr =>
      'Este dispositivo no puede mostrar este formato HDR';

  @override
  String get playbackInfoWhyAudio =>
      'Este dispositivo no puede reproducir este formato de audio';

  @override
  String get playbackInfoWhySubtitles =>
      'El servidor está grabando los subtítulos en la imagen del vídeo';

  @override
  String get playbackInfoWhyOther =>
      'El archivo no se pudo reproducir directamente';

  @override
  String playbackInfoWhyBitrateLimit(String bitrate, String limit) {
    return '$bitrate supera el límite de streaming de $limit';
  }

  @override
  String playbackInfoWhyContainerName(String container) {
    return 'Este dispositivo no puede abrir archivos $container';
  }

  @override
  String playbackInfoWhyVideoCodec(String codec) {
    return 'Este dispositivo no puede reproducir vídeo $codec';
  }

  @override
  String playbackInfoWhyVideoProfileUnknown(String codec) {
    return 'El servidor no pudo comprobar el perfil $codec de este vídeo.';
  }

  @override
  String playbackInfoWhyVideoProfile(String codec, String profile) {
    return 'Este dispositivo no puede reproducir vídeo $codec $profile';
  }

  @override
  String playbackInfoWhyVideoLevel(String codec, String level) {
    return 'Este dispositivo no puede reproducir vídeo $codec de nivel $level';
  }

  @override
  String playbackInfoWhyVideoBitDepth(int bits) {
    return 'Este dispositivo no puede reproducir vídeo de $bits bits';
  }

  @override
  String playbackInfoWhyVideoResolution(String resolution) {
    return 'Este dispositivo no puede reproducir vídeo en $resolution';
  }

  @override
  String playbackInfoWhyVideoFrameRate(String fps) {
    return 'Este dispositivo no puede reproducir vídeo a $fps fps';
  }

  @override
  String get playbackInfoWhyInterlaced =>
      'Este dispositivo no puede reproducir vídeo entrelazado';

  @override
  String get playbackInfoWhyAnamorphic =>
      'Este dispositivo no puede reproducir vídeo anamórfico';

  @override
  String playbackInfoWhyHdrName(String range) {
    return 'Este dispositivo no puede mostrar $range';
  }

  @override
  String playbackInfoWhyAudioCodec(String format) {
    return 'Este dispositivo no puede reproducir audio $format';
  }

  @override
  String playbackInfoWhyAudioProfile(String fullFormat) {
    return 'Este dispositivo no puede reproducir $fullFormat';
  }

  @override
  String playbackInfoWhyAudioChannels(String channels) {
    return 'Este dispositivo no puede reproducir audio $channels';
  }

  @override
  String playbackInfoWhyAudioSampleRate(String rate) {
    return 'Este dispositivo no puede reproducir audio a $rate kHz';
  }

  @override
  String playbackInfoWhyAudioBitDepth(int bits) {
    return 'Este dispositivo no puede reproducir audio de $bits bits';
  }

  @override
  String get playbackInfoWhyAudioExternal =>
      'La pista de audio está en un archivo aparte';

  @override
  String get playbackInfoWhySecondaryAudio =>
      'Este dispositivo solo puede reproducir la primera pista de audio';

  @override
  String playbackInfoWhySubtitleFormat(String format) {
    return 'Los subtítulos $format se están incrustando en el vídeo';
  }

  @override
  String get playbackInfoDroppedFrames => 'Fotogramas perdidos';

  @override
  String get playFromServer => 'Reproducir desde el servidor';

  @override
  String get settingsApplePlayerUi => 'Reproductor de vídeo';

  @override
  String get settingsApplePlayerUiDescription =>
      'El reproductor nativo al estilo de Apple no tiene botones de transmitir, retraso de audio ni PiP, y su bloqueo de rotación solo está en TV en directo';

  @override
  String get settingsApplePlayerUiStandard => 'Estándar';

  @override
  String get settingsApplePlayerUiNative => 'Nativo al estilo de Apple';

  @override
  String get playerTransportPosition => 'Botones de reproducción';

  @override
  String get playerTransportPositionDescription =>
      'Muestra los botones de reproducir, saltar y avanzar en el centro del vídeo o fijos en la barra inferior';

  @override
  String get playerTransportOnScreen => 'En pantalla';

  @override
  String get playerTransportDocked => 'En la barra inferior';

  @override
  String get incompleteRecording => 'Incompleta';

  @override
  String incompleteRecordingMinutes(int recorded, int expected) {
    return '$recorded de $expected min';
  }

  @override
  String completeShowingScheduled(String dateTime) {
    return 'Emisión completa programada: $dateTime';
  }

  @override
  String completeCopyRecorded(String dateTime) {
    return 'Copia completa grabada: $dateTime';
  }

  @override
  String get noCompleteShowingFound =>
      'No se encontró ninguna emisión completa';

  @override
  String get keepAsComplete => 'Marcar como completa';

  @override
  String get keptAsComplete => 'Marcada como completa';

  @override
  String get unableToKeepAsComplete => 'No se pudo marcar como completa';

  @override
  String recordPromptTitle(String name) {
    return 'Grabar $name';
  }

  @override
  String recordPromptStarted(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other:
          'Esta emisión empezó hace $minutes minutos, así que la grabación no tendrá el principio.',
      one: 'Esta emisión empezó hace 1 minuto, así que la grabación no tendrá el principio.',
    );
    return '$_temp0';
  }

  @override
  String get recordPromptAlsoRecordLater =>
      '¿Grabar también la emisión futura para tenerla completa?';

  @override
  String get recordPromptSearchLater =>
      '¿Grabar también una emisión futura automáticamente en cuanto se encuentre, para tenerla completa?';

  @override
  String get recordPromptNow => 'Ahora';

  @override
  String get recordPromptLater => 'Emisión futura';

  @override
  String recordPromptAired(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes min ya emitidos',
      one: '1 min ya emitido',
    );
    return '$_temp0';
  }

  @override
  String get recordPromptUncertainMatch =>
      'Coincide solo por título y descripción. Comprueba que es el mismo programa.';

  @override
  String get recordPromptDescriptionsDiffer =>
      'Las descripciones no coinciden, así que puede ser otro programa.';

  @override
  String recordPromptSameEpisode(int season, int episode) {
    return 'Mismo episodio (T${season}E$episode)';
  }

  @override
  String get recordPromptAlreadyScheduled => 'Ya está programada para grabarse';

  @override
  String get recordPromptTomorrow => 'mañana';

  @override
  String get recordNowOnly => 'Grabar solo ahora';

  @override
  String recordNowAnd(String when) {
    return 'Grabar ahora y $when';
  }

  @override
  String get recordNowAndLater => 'Grabar ahora y la emisión futura';

  @override
  String recordOnlyLater(String when) {
    return 'Grabar solo $when';
  }

  @override
  String get recordLaterShowingOnly => 'Grabar solo la emisión futura';

  @override
  String get laterShowingOnlyRequested => 'Se grabará la emisión futura.';

  @override
  String get unableToRequestLaterShowingOnly =>
      'No se pudo solicitar la emisión futura, así que no se grabará nada.';

  @override
  String get laterShowingRequested =>
      'Grabación iniciada. También se grabará una emisión futura.';

  @override
  String get unableToRequestLaterShowing =>
      'Grabación iniciada, pero no se pudo solicitar una emisión futura.';

  @override
  String get siloCodeSignIn => 'Iniciar sesión con un código';

  @override
  String siloCodeSignInInstruction(String address) {
    return 'Escanea el código QR con tu móvil, o ve a $address en cualquier dispositivo con la sesión iniciada e introduce este código:';
  }

  @override
  String get siloCodeSignInInstructionNoLink =>
      'Introduce este código en Silo, en un dispositivo donde tengas la sesión iniciada:';

  @override
  String get siloCodeSignInOpened =>
      'Código encontrado. Aprueba el inicio de sesión en tu otro dispositivo.';

  @override
  String get siloCodeSignInDenied => 'Se ha rechazado este inicio de sesión.';

  @override
  String get siloCodeSignInNewCode => 'Obtener un código nuevo';

  @override
  String get siloCodeSignInOff =>
      'El inicio de sesión con código está desactivado en este servidor.';

  @override
  String get siloCodeSignInPasswordChangeRequired =>
      'Esta cuenta tiene una contraseña temporal. Inicia sesión una vez con la contraseña para cambiarla.';

  @override
  String get siloApproveSignIn => 'Aprobar un inicio de sesión';

  @override
  String get siloApproveSignInHint => 'Código que muestra el otro dispositivo';

  @override
  String get siloApproveSignInApprove => 'Aprobar';

  @override
  String get siloApproveSignInDone =>
      'Aprobado. El otro dispositivo está iniciando sesión.';

  @override
  String get siloApproveSignInNoRequest =>
      'No hay ningún inicio de sesión pendiente con ese código. Compruébalo u obtén un código nuevo en el otro dispositivo.';

  @override
  String get siloNativeOfferTitle => '¿Conectar directamente con Silo?';

  @override
  String siloNativeOfferMessage(String serverName, String address) {
    return 'Esta dirección es el servicio compatible con Jellyfin de $serverName. kOS TV puede conectarse directamente a Silo en $address, con las funciones propias de Silo.';
  }

  @override
  String get siloNativeOfferUse => 'Usar Silo';

  @override
  String get siloNativeOfferKeep => 'Mantener Jellyfin';

  @override
  String get siloAppUpdateRequired =>
      'Este servidor Silo necesita una versión más reciente de kOS TV. Actualiza kOS TV para usarlo.';

  @override
  String get siloServerUpdateRequired =>
      'Este servidor Silo es demasiado antiguo para esta versión de kOS TV. Actualiza Silo para usarlo.';

  @override
  String get siloTooManyAttempts =>
      'Demasiados intentos. Vuelve a intentarlo más tarde.';

  @override
  String siloTooManyAttemptsWait(String wait) {
    return 'Demasiados intentos. Vuelve a intentarlo dentro de $wait.';
  }

  @override
  String get siloServerBusy =>
      'El servidor está ocupado o todavía se está iniciando. Vuelve a intentarlo más tarde.';

  @override
  String siloServerBusyWait(String wait) {
    return 'El servidor está ocupado o todavía se está iniciando. Vuelve a intentarlo dentro de $wait.';
  }

  @override
  String siloWaitSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count segundos',
      one: '1 segundo',
    );
    return '$_temp0';
  }

  @override
  String siloWaitMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutos',
      one: '1 minuto',
    );
    return '$_temp0';
  }

  @override
  String get siloPlaybackUnavailable =>
      'La reproducción no está disponible en este servidor Silo.';

  @override
  String get siloPlaybackUpdateRequired =>
      'Este servidor Silo necesita una versión más reciente de kOS TV para reproducir.';

  @override
  String get siloPlaybackEndedOnServer =>
      'La reproducción se ha terminado desde el servidor Silo.';

  @override
  String siloPinTitle(String name) {
    return 'PIN de $name';
  }

  @override
  String get siloPinHint => 'PIN';

  @override
  String get siloPinUnlock => 'Desbloquear';

  @override
  String get siloPinRemember => 'Recordar el PIN en este dispositivo';

  @override
  String get siloPinWrong => 'Ese PIN no es correcto.';

  @override
  String get siloPinLocked =>
      'Demasiados PIN incorrectos. Vuelve a intentarlo más tarde.';

  @override
  String siloPinLockedWait(String wait) {
    return 'Demasiados PIN incorrectos. Vuelve a intentarlo dentro de $wait.';
  }

  @override
  String get siloPinFailed =>
      'No se pudo comprobar el PIN. Vuelve a intentarlo.';

  @override
  String trailerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tráileres',
      one: '1 tráiler',
    );
    return '$_temp0';
  }

  @override
  String trailerNumber(int number) {
    return 'Tráiler $number';
  }

  @override
  String get subtitled => 'Subtitulado';

  @override
  String get rommAccount => 'Cuenta de RomM';

  @override
  String get rommAccountIntro =>
      'Vincula tu cuenta de RomM para jugar desde tu propia biblioteca de RomM y guardar tus partidas en RomM.';

  @override
  String get rommLinkAccount => 'Vincular cuenta de RomM';

  @override
  String get rommLinkInstructions =>
      'Inicia sesión en RomM e introduce este código para vincular tu cuenta.';

  @override
  String rommLinkScanOrVisit(String url) {
    return 'Escanea el código QR con tu móvil, o ve a $url';
  }

  @override
  String get rommOpen => 'Abrir RomM';

  @override
  String get rommWaitingForApproval =>
      'Esperando a que apruebes el código en RomM...';

  @override
  String rommLinkedAs(String username) {
    return 'Vinculada como $username';
  }

  @override
  String get rommLinked => 'Tu cuenta de RomM está vinculada.';

  @override
  String get rommUnlinkNote =>
      'Al desvincularla, kOS TV deja de usar tu clave de RomM. La clave sigue en RomM hasta que la borres de tus tokens de API allí.';

  @override
  String get rommUnlink => 'Desvincular';

  @override
  String get rommLinkExpired =>
      'El código caducó antes de aprobarse. Vuelve a vincular para obtener uno nuevo.';

  @override
  String get rommLinkDenied => 'La vinculación se ha rechazado en RomM.';

  @override
  String get rommUnreachable =>
      'kOS TV no pudo conectar con RomM. Vuelve a intentarlo en un momento.';

  @override
  String get rommNotAvailable => 'Este servidor no tiene biblioteca de RomM.';

  @override
  String get rommAccountLoadFailed => 'No se pudo cargar tu cuenta de RomM.';

  @override
  String get reviews => 'Reseñas';

  @override
  String get detailSectionReviews => 'Reseñas';

  @override
  String spotlightReviewsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reseñas',
      one: '1 reseña',
    );
    return '$_temp0';
  }

  @override
  String get readOnTmdb => 'Leer en TMDB';

  @override
  String get addServerButtonSubtitle =>
      'Por dirección, o con una cuenta de Plex o Emby Connect';

  @override
  String get addServerChooseHow => 'Elige cómo quieres conectarte.';

  @override
  String get addServerAddressChoice =>
      'Jellyfin, Emby o Silo en tu red o en internet';

  @override
  String get addServerPlexChoice =>
      'Usa tu cuenta de Plex para encontrar sus servidores';

  @override
  String get addServerAddressHelp =>
      'La misma dirección que abrirías en un navegador, con el puerto.';

  @override
  String get addServerDetectNote =>
      'Funciona con Jellyfin, Emby y Silo. Una dirección de Plex abre el inicio de sesión de Plex.';

  @override
  String addServerChecking(String address) {
    return 'Comprobando $address';
  }

  @override
  String get addServerUnreachableDetail =>
      'Comprueba la dirección y el puerto, y que el servidor esté en marcha.';

  @override
  String get addServerFound => 'Servidor encontrado';

  @override
  String get addServerFoundNote => 'Continúa para elegir quién inicia sesión.';

  @override
  String get addServerUseDifferentAddress => 'Usar otra dirección';

  @override
  String musicArtistCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count artistas',
      one: '1 artista',
    );
    return '$_temp0';
  }

  @override
  String musicSongCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count canciones',
      one: '1 canción',
    );
    return '$_temp0';
  }

  @override
  String musicPlaylistCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count listas de reproducción',
      one: '1 lista de reproducción',
    );
    return '$_temp0';
  }

  @override
  String musicPlayCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reproducciones',
      one: '1 reproducción',
    );
    return '$_temp0';
  }

  @override
  String get allArtists => 'Todos los artistas';

  @override
  String get libraryZToA => 'De la Z a la A';

  @override
  String get musicSortYear => 'Año';

  @override
  String get musicFilter => 'Filtrar';

  @override
  String get musicGenreFilterTitle => 'Filtrar por género';

  @override
  String get openAlbum => 'Abrir álbum';

  @override
  String get openPlaylist => 'Abrir lista de reproducción';

  @override
  String get allSongsAToZ => 'Todas las canciones de la A a la Z';

  @override
  String get musicMix => 'Mezcla';

  @override
  String get musicMixEverything => 'Todo';

  @override
  String get musicMixEverythingSubtitle => '300 canciones al azar';

  @override
  String get mostPlayed => 'Más escuchadas';

  @override
  String get musicMixMostPlayedSubtitle => 'Tus 100 más escuchadas';

  @override
  String get musicMixFreshArrivals => 'Recién llegadas';

  @override
  String get musicMixFreshArrivalsSubtitle => 'Las 100 canciones más nuevas';

  @override
  String get musicMixRediscover => 'Redescubre';

  @override
  String get musicMixRediscoverSubtitle =>
      'Favoritas que no has escuchado últimamente';

  @override
  String get musicSortMostAlbums => 'Más álbumes';

  @override
  String bookSeriesPosition(int index, int total) {
    return 'Libro $index de $total';
  }

  @override
  String bookFavoriteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count favoritos',
      one: '1 favorito',
    );
    return '$_temp0';
  }

  @override
  String get bookSortZToA => 'De la Z a la A';

  @override
  String get bookSortMostTitles => 'Más títulos';

  @override
  String get bookSurpriseMe => 'Sorpréndeme';

  @override
  String get bookShuffleAudiobooks => 'Audiolibros al azar';

  @override
  String get bookStartReading => 'Empezar a leer';

  @override
  String get bookOtherBooks => 'Otros libros';

  @override
  String get bookDiscoverSearchBooks => 'Buscar en Open Library';

  @override
  String get bookDiscoverSearchAudiobooks => 'Buscar en LibriVox';

  @override
  String get bookDiscoverFeatured => 'Destacado';

  @override
  String get bookReaderControlsAutoHide => 'Los controles se ocultan solos';

  @override
  String get bookReaderControlsStayVisible =>
      'Los controles se quedan a la vista';

  @override
  String get settingsLivePreview => 'Vista previa en directo';

  @override
  String settingsPreviewShowsOn(String screen) {
    return 'Se ve en la vista previa de $screen';
  }

  @override
  String get settingsPreviewNotShown => 'No se ve en la vista previa';

  @override
  String settingsPreviewAudioRowsOffInHomeRows(String group, String disabled) {
    return 'Álbumes, Artistas y Listas de reproducción de audio están desactivadas. Para mostrar alguna, ve a Filas, abre $group en $disabled y actívala.';
  }

  @override
  String settingsPreviewAudioRowsOffInHomeRowsSwitchOff(
    String setting,
    String group,
    String disabled,
  ) {
    return 'Para ver Álbumes, Artistas o Listas de reproducción de audio en Inicio, primero activa $setting. Después ve a Filas, abre $group en $disabled y activa alguna.';
  }

  @override
  String settingsPreviewCollectionsOffInHomeRows(
    String group,
    String disabled,
  ) {
    return 'La fila Colecciones está desactivada. Para mostrarla, ve a Filas, abre $group en $disabled y actívala.';
  }

  @override
  String settingsPreviewCollectionsOffInHomeRowsSwitchOff(
    String setting,
    String group,
    String disabled,
  ) {
    return 'Para ver la fila Colecciones en Inicio, primero activa $setting. Después ve a Filas, abre $group en $disabled y actívala.';
  }

  @override
  String get settingsPreviewRowsOffInKidsMode =>
      'El modo infantil oculta estas filas en Inicio, así que estos ajustes no lo cambian.';

  @override
  String settingsPreviewNeedsRowInRows(String disabled) {
    return 'Activa una fila en Filas, en $disabled';
  }

  @override
  String settingsPreviewNeedsSwitchAndRow(String setting) {
    return 'Activa $setting y después una fila en Filas';
  }

  @override
  String get settingsPreviewKeptOffByKidsMode =>
      'El modo infantil oculta esto en Inicio';

  @override
  String get settingsPreviewAudioRowsEmpty =>
      'No hay música que mostrar, así que Inicio no muestra estas filas.';

  @override
  String get settingsPreviewCollectionsEmpty =>
      'No hay colecciones que mostrar, así que Inicio no muestra esta fila.';

  @override
  String get settingsPreviewShowEpisodesNote =>
      'Esto solo cambia las filas de una colección concreta añadida en Filas. La fila Colecciones se ve igual.';

  @override
  String get settingsPreviewSaved => 'Guardado';

  @override
  String get smartSearch => 'Búsqueda inteligente';

  @override
  String get calendar => 'Calendario';

  @override
  String get showCalendarButton => 'Mostrar botón de calendario';

  @override
  String get showCalendarButtonSubtitle =>
      'Muestra el calendario de próximos episodios y películas en la barra de navegación';

  @override
  String get calendarFullCalendar => 'Calendario completo';

  @override
  String get calendarUpcoming => 'Próximamente';

  @override
  String get calendarRecentlyAired => 'Emitido recientemente';

  @override
  String get calendarRemindMe => 'Recuérdamelo';

  @override
  String get calendarReminderSet => 'Recordatorio activado';

  @override
  String get calendarReminderFailed => 'No se pudo guardar el recordatorio';

  @override
  String get calendarReadyToWatch => 'Listo para ver';

  @override
  String get calendarComingUpThisWeek => 'Llega esta semana';

  @override
  String get calendarNothingUpcoming => 'No hay nada próximamente';

  @override
  String get calendarNothingRecent => 'No se ha emitido nada recientemente';

  @override
  String get calendarEmptyDay => 'No hay nada este día';

  @override
  String get calendarStartsIn => 'Empieza en';

  @override
  String get calendarUnitDays => 'días';

  @override
  String get calendarUnitHours => 'h';

  @override
  String get calendarUnitMinutes => 'min';

  @override
  String calendarDayAtTime(String day, String time) {
    return '$day a las $time';
  }

  @override
  String get calendarAllDay => 'Todo el día';

  @override
  String get calendarBadgeSeriesPremiere => 'Estreno de la serie';

  @override
  String get calendarBadgeSeasonPremiere => 'Nueva temporada';

  @override
  String get calendarBadgeSeasonFinale => 'Final de temporada';

  @override
  String get calendarBadgeMidseasonFinale => 'Final de mitad de temporada';

  @override
  String get calendarBadgeSeriesFinale => 'Final de la serie';

  @override
  String get calendarBadgeNew => 'NUEVO';

  @override
  String get calendarStatusInLibrary => 'En la biblioteca';

  @override
  String get calendarNotMonitored => 'Sin seguimiento';

  @override
  String get calendarMovieDetails => 'Detalles de la película';

  @override
  String get calendarProblemAdminsOnly =>
      'En este servidor, el calendario es solo para administradores.';

  @override
  String get calendarProblemNotConfigured =>
      'Todavía no hay ningún servidor Sonarr o Radarr vinculado.';

  @override
  String get calendarProblemFailed => 'No se pudo cargar el calendario.';

  @override
  String get calendarRowSeeAll => 'Tarjeta Ver todo';

  @override
  String get calendarRowSeeAllSubtitle =>
      'Termina las filas de próximos estrenos con una tarjeta que abre el calendario';

  @override
  String get showNextAirDate => 'Próxima emisión al final';

  @override
  String get showNextAirDateSubtitle =>
      'Cuando el siguiente episodio aún no está en tu biblioteca, la tarjeta de final de episodio dice cuándo se emite';

  @override
  String get afterHoursTitle => 'After Hours';

  @override
  String get afterHoursUnlocked => 'After Hours desbloqueado';

  @override
  String afterHoursPressesLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pulsaciones más',
      one: '1 pulsación más',
    );
    return '$_temp0';
  }

  @override
  String afterHoursTapsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count toques más',
      one: '1 toque más',
    );
    return '$_temp0';
  }

  @override
  String get afterHoursPlay => 'Jugar';

  @override
  String get afterHoursLeaderboards => 'Clasificaciones';

  @override
  String get afterHoursTop3 => 'Top 3';

  @override
  String afterHoursScoresFrom(String server) {
    return 'Puntuaciones de $server';
  }

  @override
  String get afterHoursScoresOnDevice => 'Puntuaciones de este dispositivo';

  @override
  String get afterHoursGameOver => 'Fin de la partida';

  @override
  String afterHoursNewRank(int rank) {
    return 'Nuevo n.º $rank de la clasificación';
  }

  @override
  String get afterHoursPlayAgain => 'Jugar otra vez';

  @override
  String get afterHoursBackToArcade => 'Volver a los recreativos';

  @override
  String get afterHoursArcade => 'Recreativos';

  @override
  String get afterHoursLandscapeNote => 'Se pone en horizontal mientras juegas';

  @override
  String get afterHoursTouch => 'Táctil';

  @override
  String get afterHoursNewTag => 'NUEVO';

  @override
  String get afterHoursNoScores => 'Aún no hay puntuaciones';

  @override
  String get afterHoursPerfect => 'PERFECTO';

  @override
  String get afterHoursBoxSet => 'PACK';

  @override
  String get afterHoursBufferRun => 'Buffer Run';

  @override
  String get afterHoursBufferRunGenre =>
      'Carrera sin fin con cambio de gravedad';

  @override
  String get afterHoursBufferRunPitch =>
      'El corredor de la pantalla de carga por fin tiene adónde ir. Con un doble salto, la gravedad lo lleva al techo.';

  @override
  String get afterHoursBufferRunRemote =>
      'OK salta y en el aire cambia de lado. Abajo desliza. En el techo, Arriba y Abajo se invierten.';

  @override
  String get afterHoursBufferRunTouch =>
      'Toca para saltar, y en el aire para cambiar de lado. Desliza hacia tu lado para deslizarte.';

  @override
  String get afterHoursFastForward => 'Fast Forward';

  @override
  String get afterHoursFastForwardGenre => 'Carrera en tres carriles';

  @override
  String get afterHoursFastForwardPitch =>
      'Un sprint por tres pasillos del vestíbulo del cine. Salta lo bajo, y recuerda que los carritos de palomitas no se apartan por nadie.';

  @override
  String get afterHoursFastForwardRemote =>
      'Arriba y Abajo cambian de carril. OK salta.';

  @override
  String get afterHoursFastForwardTouch =>
      'Desliza arriba o abajo para cambiar de carril. Toca para saltar.';

  @override
  String get afterHoursCableCrawl => 'Cable Crawl';

  @override
  String get afterHoursCableCrawlGenre => 'Serpiente en cuadrícula';

  @override
  String get afterHoursCableCrawlPitch =>
      'Guía un cable HDMI por detrás del mueble de la tele y conéctalo a la señal. Cada barra lo alarga.';

  @override
  String get afterHoursCableCrawlRemote =>
      'Las flechas giran. El cable nunca se para.';

  @override
  String get afterHoursCableCrawlTouch => 'Desliza para girar.';

  @override
  String get afterHoursCaseStack => 'Case Stack';

  @override
  String get afterHoursCaseStackGenre => 'Apilador de un botón';

  @override
  String get afterHoursCaseStackPitch =>
      'Levanta hasta la altura de la estantería una torre de cajas de Blu-ray, cada una con un título de tu propia biblioteca. Lo que sobresale del borde se recorta, así que suéltalas justo encima.';

  @override
  String get afterHoursCaseStackRemote => 'OK suelta la caja.';

  @override
  String get afterHoursCaseStackTouch => 'Toca en cualquier sitio para soltar.';

  @override
  String get afterHoursPixelPurge => 'Pixel Purge';

  @override
  String get afterHoursPixelPurgeGenre => 'Rompeladrillos con pala';

  @override
  String get afterHoursPixelPurgePitch =>
      'Una mala codificación ha llenado la imagen de artefactos cuadrados, y bajan un poco cada segundo. Haz rebotar el botón de reproducir en la barra de progreso para eliminarlos antes de que lleguen a ella.';

  @override
  String get afterHoursPixelPurgeRemote =>
      'Izquierda y Derecha mueven la barra. La bola sale sola.';

  @override
  String get afterHoursPixelPurgeTouch => 'Arrastra para mover la barra.';

  @override
  String get afterHoursHowToPlay => 'Cómo se juega';

  @override
  String get afterHoursStart => 'Empezar';

  @override
  String get afterHoursBackToGame => 'Volver a la partida';

  @override
  String get afterHoursEnemies => 'Enemigos';

  @override
  String get afterHoursObstacles => 'Obstáculos';

  @override
  String get afterHoursPowerups => 'Potenciadores';

  @override
  String get afterHoursCastShieldLine => 'Un escudo que aguanta un golpe.';

  @override
  String get afterHoursCastPointsLine => '25 puntos cada uno.';

  @override
  String get afterHoursCastLagBat => 'Murciélago del lag';

  @override
  String get afterHoursCastLagBatLine =>
      'Baja en picado a la altura de la cabeza. Pasa por debajo.';

  @override
  String get afterHoursCastGremlin => 'Gremlin de estática';

  @override
  String get afterHoursCastGremlinLine =>
      'Va dando saltos por el suelo o el techo hacia ti. Sáltalo.';

  @override
  String get afterHoursCastCable => 'Rollo de cable';

  @override
  String get afterHoursCastCableLine =>
      'Bajo, en el suelo o en el techo. Sáltalo.';

  @override
  String get afterHoursCastBanner => 'Cartel de carga';

  @override
  String get afterHoursCastBannerLine =>
      'Deslízate bajo el cartel. Su poste es un muro al otro lado.';

  @override
  String get afterHoursCastSkipIntro => 'Saltar intro';

  @override
  String get afterHoursCastSkipIntroLine =>
      'Tres segundos de carrera que lo arrasa todo.';

  @override
  String get afterHoursCastPopcorn => 'Palomitas';

  @override
  String get afterHoursCastRollingReel => 'Bobina suelta';

  @override
  String get afterHoursCastRollingReelLine =>
      'Rueda por tu carril más rápido de lo que corres. Sáltala.';

  @override
  String get afterHoursCastUsher => 'Acomodador';

  @override
  String get afterHoursCastUsherLine =>
      'Camina hacia ti y cambia de carril una vez.';

  @override
  String get afterHoursCastVelvetRope => 'Cordón de terciopelo';

  @override
  String get afterHoursCastVelvetRopeLine =>
      'Bajo. Sáltalo o cambia de carril.';

  @override
  String get afterHoursCastPopcornCart => 'Carrito de palomitas';

  @override
  String get afterHoursCastPopcornCartLine =>
      'Demasiado alto para saltarlo. Cambia de carril.';

  @override
  String get afterHoursCastFrontRowPass => 'Pase de primera fila';

  @override
  String get afterHoursCastMagnet => 'Imán';

  @override
  String get afterHoursCastMagnetLine =>
      'Atrae entradas de todos los carriles durante ocho segundos.';

  @override
  String get afterHoursCastTicket => 'Entrada';

  @override
  String get afterHoursCastBug => 'Bicho de interferencias';

  @override
  String get afterHoursCastBugLine => 'Deambula al azar.';

  @override
  String get afterHoursCastTangle => 'Maraña';

  @override
  String get afterHoursCastTangleLine => 'Persigue despacio a tu clavija.';

  @override
  String get afterHoursCastStatic => 'Estática';

  @override
  String get afterHoursCastStaticLine =>
      'Una casilla muerta. Aparece una cada tres señales.';

  @override
  String get afterHoursCastBrick => 'Transformador';

  @override
  String get afterHoursCastBrickLine =>
      'Un bloque de 2 por 2 cada cinco señales.';

  @override
  String get afterHoursCastGhost => 'Fantasma';

  @override
  String get afterHoursCastGhostLine =>
      'Cinco segundos atravesándolo todo menos el borde.';

  @override
  String get afterHoursCastSnip => 'Tijeretazo';

  @override
  String get afterHoursCastSnipLine =>
      'Corta el cable por la mitad y da puntos extra.';

  @override
  String get afterHoursCastSignal => 'Señal';

  @override
  String get afterHoursCastSignalLine => 'Puntos y dos segmentos más.';

  @override
  String get afterHoursCastShelfCat => 'Gato del estante';

  @override
  String get afterHoursCastShelfCatLine =>
      'Da un zarpazo a la caja que llega y la hace ir más rápido.';

  @override
  String get afterHoursCastBluCase => 'Caja de Blu-ray';

  @override
  String get afterHoursCastBluCaseLine =>
      'Un título de tu biblioteca. Lo que sobresale se recorta.';

  @override
  String get afterHoursCastSteelbook => 'Steelbook';

  @override
  String get afterHoursCastSteelbookLine =>
      'Una de cada diez cajas. Se desliza mucho más rápido.';

  @override
  String get afterHoursCastPerfect => 'Caída perfecta';

  @override
  String get afterHoursCastPerfectLine =>
      'Suéltala justo encima y la pila se ensancha un poco.';

  @override
  String get afterHoursCastBoxSet => 'Pack';

  @override
  String get afterHoursCastBoxSetLine =>
      'Tres caídas perfectas seguidas la ensanchan mucho más.';

  @override
  String get afterHoursCastDeadPixel => 'Píxel muerto';

  @override
  String get afterHoursCastDeadPixelLine =>
      'Cae de los bloques rotos. Si lo atrapas, la barra encoge.';

  @override
  String get afterHoursCastMacroblock => 'Macrobloque';

  @override
  String get afterHoursCastMacroblockLine => 'Se elimina de un golpe.';

  @override
  String get afterHoursCastKeyframe => 'Fotograma clave';

  @override
  String get afterHoursCastKeyframeLine =>
      'Aguanta tres golpes y suelta un potenciador.';

  @override
  String get afterHoursCastHdrLine =>
      'Una barra el doble de ancha durante ocho segundos.';

  @override
  String get afterHoursCastBufferNet => 'Búfer';

  @override
  String get afterHoursCastBufferNetLine =>
      'Una red bajo la barra que te salva de un fallo.';

  @override
  String get afterHoursBufferRunCardTouch =>
      'Toca para saltar o, en el aire, cambiar de lado. Desliza hacia tu lado para deslizarte.';

  @override
  String get afterHoursPixelPurgeCardRemote =>
      'Izquierda y Derecha mueven la barra.';

  @override
  String get kostvServerPlugin => 'Complemento del servidor';

  @override
  String get kostvTmdbListsUnavailable =>
      'Configura la clave de la API de TMDB en los ajustes del complemento del servidor para usar esta función.';

  @override
  String get kostvDownloadingListFromPlugin =>
      'Descargando la lista del complemento del servidor y guardándola aquí...';

  @override
  String kostvFetchListFailed(String title, String error) {
    return 'No se pudo descargar $title del complemento del servidor: $error';
  }

  @override
  String get kostvDiagnostics => 'Diagnóstico y registros';

  @override
  String get kostvDiagnosticsSubtitle =>
      'Guarda registros de reproducción, inicio de sesión y red y envíalos al servidor como informe';

  @override
  String get kostvTmdbTopRatedMovies => 'Películas mejor valoradas';

  @override
  String get kostvTmdbNowPlayingMovies => 'En cines';

  @override
  String get kostvTmdbPopularTv => 'Series populares';

  @override
  String get kostvTmdbTopRatedTv => 'Series mejor valoradas';

  @override
  String get kostvTmdbAiringTodayTv => 'Series que se emiten hoy';

  @override
  String get kostvTmdbOnTheAirTv => 'Series en emisión';

  @override
  String get kostvTmdbTrendingMoviesDaily => 'Películas en tendencia (hoy)';

  @override
  String get kostvTmdbTrendingMoviesWeekly =>
      'Películas en tendencia (esta semana)';

  @override
  String get kostvTmdbTrendingTvDaily => 'Series en tendencia (hoy)';

  @override
  String get kostvTmdbTrendingTvWeekly => 'Series en tendencia (esta semana)';

  @override
  String get kostvTmdbTrendingAllWeekly => 'En tendencia (esta semana)';

  @override
  String get kostvRewatchRow => 'Volver a ver';

  @override
  String get kostvAppsRow => 'Aplicaciones';

  @override
  String get kostvAllApps => 'Todas las aplicaciones';

  @override
  String get kostvTvSettings => 'Ajustes de la tele';

  @override
  String get kostvAppOpen => 'Abrir';

  @override
  String get kostvAppAddToHome => 'Añadir a Inicio';

  @override
  String get kostvAppRemoveFromHome => 'Quitar de Inicio';

  @override
  String get kostvAppMoveLeft => 'Mover a la izquierda';

  @override
  String get kostvAppMoveRight => 'Mover a la derecha';

  @override
  String kostvAppCouldNotOpen(String app) {
    return 'No se ha podido abrir $app.';
  }

  @override
  String get kostvShowAppsRow => 'Fila de aplicaciones en Inicio';

  @override
  String get kostvShowAppsRowSubtitle =>
      'Muestra en Inicio las aplicaciones de la tele';

  @override
  String get kostvShowAppsButton => 'Pantalla de aplicaciones en el menú';

  @override
  String get kostvPersonalization => 'Personalización';

  @override
  String get kostvCustomizeLook => 'Personalizar el aspecto';

  @override
  String get kostvCustomizeLookSubtitle =>
      'Elige cómo se ven la navegación, Inicio y las fichas';

  @override
  String get kostvDiscover => 'Descubrir';

  @override
  String get kostvDiscoverAll => 'Todo';

  @override
  String get kostvShowDiscoverButton => 'Botón Descubrir';

  @override
  String get kostvDiscoverPopularSeries => 'Series más vistas';

  @override
  String get kostvDiscoverNewSeries => 'Series nuevas';

  @override
  String get kostvDiscoverPopularMovies => 'Películas más vistas';

  @override
  String get kostvDiscoverNewMovies => 'Películas nuevas';

  @override
  String kostvDiscoverPopularSeriesOn(String platform) {
    return 'Series más vistas en $platform';
  }

  @override
  String kostvDiscoverNewSeriesOn(String platform) {
    return 'Series nuevas en $platform';
  }

  @override
  String kostvDiscoverPopularMoviesOn(String platform) {
    return 'Películas más vistas en $platform';
  }

  @override
  String kostvDiscoverNewMoviesOn(String platform) {
    return 'Películas nuevas en $platform';
  }

  @override
  String get kostvDiscoverInLibrary => 'Ya está';

  @override
  String kostvDiscoverMissingSeason(int season) {
    return 'Falta la T$season';
  }

  @override
  String get kostvDiscoverComingSoon => 'Llega pronto';

  @override
  String get kostvDiscoverRequested => 'Solicitada';

  @override
  String get kostvDiscoverRequestedByYou => 'Solicitada por ti';

  @override
  String get kostvDiscoverBrandNewSeries => 'Serie nueva';

  @override
  String kostvDiscoverNewSeason(int season) {
    return 'T$season nueva';
  }

  @override
  String kostvDiscoverNotHereYet(String title) {
    return '$title todavía no está en kOS TV.';
  }

  @override
  String get kostvDiscoverUnavailable =>
      'Descubrir no está disponible ahora mismo.';

  @override
  String get kostvMoreSettings => 'Más ajustes';

  @override
  String get kostvFewerSettings => 'Menos ajustes';

  @override
  String get kostvRefreshingCustomRows =>
      'Actualizando las filas personalizadas';

  @override
  String get kostvRefreshingCustomRowsDetail =>
      'Actualizando tus filas personalizadas y lo que guardan…';

  @override
  String get kostvCustomRowsRefreshed =>
      'Tus filas personalizadas están al día.';

  @override
  String kostvCustomRowsRefreshFailed(String detail) {
    return 'No se han podido actualizar las filas personalizadas: $detail';
  }

  @override
  String get kostvImdbLists => 'Listas de IMDb';

  @override
  String get kostvImdbListsSubtitle =>
      'El Top 250 de IMDb, lo más popular y otras listas como filas de Inicio.';

  @override
  String get kostvTmdbLists => 'Listas de TMDB';

  @override
  String get kostvTmdbListsSubtitle =>
      'Lo popular, lo mejor valorado y lo que es tendencia en TMDB.';

  @override
  String get kostvCustomRows => 'Filas personalizadas';

  @override
  String get kostvCustomRowsSubtitle =>
      'Filas de Inicio hechas con listas de Letterboxd, TMDB, MDBList, IMDb y más.';

  @override
  String get kostvMediaTypeBadges => 'Etiquetas de película y serie';

  @override
  String get kostvMediaTypeBadgesSubtitle =>
      'Muestra PELÍCULA o SERIE en las tarjetas de las filas de listas de fuera.';

  @override
  String get kostvRefreshCustomRows => 'Actualizar las filas personalizadas';

  @override
  String get kostvRefreshCustomRowsSubtitle =>
      'Vuelve a traer ahora todas las filas personalizadas.';

  @override
  String get kostvMoreAccountSummary =>
      'Pedir siempre la contraseña, sincronización de ajustes';

  @override
  String get kostvMoreGeneralSummary =>
      'Reloj de 24 horas, formato de fecha, salir, rendimiento…';

  @override
  String get kostvMoreAppearanceSummary =>
      'Estilo de la interfaz, color de enfoque, temas, pantalla y animaciones';

  @override
  String get kostvMoreHomeSummary =>
      'Opciones de las filas, su aspecto, valoraciones y listas de fuera';

  @override
  String get kostvMorePlaybackSummary =>
      'Calidad y decodificación, juegos y reproducción avanzada';

  @override
  String get kostvMoreStorageSummary =>
      'Ubicación de las descargas, descargas a la vez, caché de imágenes…';

  @override
  String get kostvMoreAboutSummary =>
      'Código fuente, diagnóstico y registros, atajos de teclado';

  @override
  String get kostvTmdbPopularMovies => 'Películas populares';

  @override
  String get kostvTmdbUpcomingMovies => 'Próximos estrenos';

  @override
  String get kostvDisplayRewatchRow => 'Fila «Volver a ver»';

  @override
  String get kostvDisplayRewatchRowSubtitle =>
      'Muestra en Inicio la fila de lo que puedes volver a ver.';

  @override
  String get kostvSendCrashReports => 'Enviar informes de errores al servidor';

  @override
  String get kostvStillWatchingSubtitle =>
      'Pregunta si sigues viendo después de varios episodios seguidos.';

  @override
  String get kostvMorePlayerSummary =>
      'Zoom, retroceso al reanudar, controles, botones y miniaturas';

  @override
  String get kostvMoreAudioSummary =>
      'Idioma alternativo, audiodescripción, passthrough y códecs';

  @override
  String get kostvMoreAudioSummaryWeb =>
      'Idioma alternativo y audiodescripción';

  @override
  String get kostvMoreSubtitlesSummary =>
      'Idiomas para descargar, subtítulos secundarios, SDH, PGS y ASS';

  @override
  String get kostvMoreSubtitleStyleSummary =>
      'Trazo, negrita, fuente, sombra y estilo para HDR';

  @override
  String get kostvMoreSkipsSummary =>
      'Modo cine, otros segmentos, botón de saltar y A continuación';

  @override
  String get kostvMoreWatchTogetherSummary =>
      'Chat, avisos de salas y sincronización de SyncPlay';

  @override
  String get kostvAudioOutputSection => 'Salida de audio';

  @override
  String get kostvAudioRedetect => 'Volver a detectar el audio';

  @override
  String get kostvAudioRedetectSubtitle =>
      'Vuelve a detectar la salida de audio y recupera los ajustes recomendados.';

  @override
  String kostvAudioRedetected(String route) {
    return 'Audio detectado de nuevo: $route';
  }

  @override
  String get kostvDecodingRenderingSection => 'Decodificación y renderizado';

  @override
  String get kostvMoreNavigationSummary =>
      'Color y opacidad de la barra, etiquetas y qué botones salen';

  @override
  String get kostvMoreMediaBarSummary =>
      'Qué títulos salen y de dónde, valoraciones, avance automático…';

  @override
  String get kostvMoreLibrariesSummary =>
      'Estilos de biblioteca, colecciones, títulos bajo los pósteres, libros…';

  @override
  String get kostvMoreDetailsSummary =>
      'Fondo, botones, datos y secciones, recomendaciones, valoraciones…';

  @override
  String get kostvMoreScreensaverSummary =>
      'Atenuación, suspender la tele, movimiento y qué imágenes salen';

  @override
  String get kostvLogging => 'Registro';

  @override
  String get kostvDiagnosticLogging => 'Registro de diagnóstico';

  @override
  String get kostvDiagnosticLoggingSubtitle =>
      'Guarda datos de reproducción, de red y otros diagnósticos para poder enviarlos al servidor como informe.';

  @override
  String get kostvSendCrashReportsSubtitle =>
      'Si la app se cierra por un fallo, guarda un informe y lo envía a tu servidor la próxima vez que se conecte. No se envía a ningún otro sitio.';

  @override
  String get kostvReports => 'Informes';

  @override
  String kostvReportsCaptured(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Informes ($count entradas guardadas)',
      one: 'Informes (1 entrada guardada)',
    );
    return '$_temp0';
  }

  @override
  String get kostvSendReport => 'Enviar informe al servidor';

  @override
  String get kostvSendReportSubtitle =>
      'Sube los registros guardados al servidor que estás usando.';

  @override
  String get kostvTurnOnLoggingFirst =>
      'Primero activa el registro de diagnóstico.';

  @override
  String get kostvNoLogEntriesCaptured => 'Todavía no se ha guardado nada.';

  @override
  String get kostvReportNeedsSignIn =>
      'Inicia sesión en un servidor para enviar informes.';

  @override
  String get kostvReportNeedsPlugin =>
      'Este servidor necesita el complemento del servidor con la subida de registros activada.';

  @override
  String get kostvReportNotSupported =>
      'El servidor que estás usando no admite informes.';

  @override
  String get kostvCopyAllLogs => 'Copiar todos los registros';

  @override
  String get kostvCopyAllLogsSubtitle =>
      'Copia el informe completo al portapapeles.';

  @override
  String get kostvClearLogs => 'Borrar los registros guardados';

  @override
  String get kostvClearLogsSubtitle =>
      'Descarta todo lo que se ha guardado hasta ahora.';

  @override
  String get kostvRecentLogs => 'Registros recientes';

  @override
  String kostvRecentLogsFiltered(int shown, int total) {
    return 'Registros recientes ($shown de $total)';
  }

  @override
  String get kostvAllCategories => 'Todas las categorías';

  @override
  String get kostvLogCategoryMedia => 'Multimedia';

  @override
  String get kostvLogCategorySync => 'Sincronización';

  @override
  String get kostvLogCategoryArtwork => 'Imágenes';

  @override
  String kostvNoLogEntriesInCategory(int total, String category) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other:
          'Nada en «$category». Hay $total en otras categorías: cambia el filtro para verlas.',
      one:
          'Nada en «$category». Hay 1 entrada en otra categoría: cambia el filtro para verla.',
    );
    return '$_temp0';
  }

  @override
  String get kostvNoLogEntriesYet =>
      'Todavía no hay registros. Haz que vuelva a pasar el problema y luego envía un informe.';

  @override
  String get kostvLoggingOff =>
      'El registro está apagado. Actívalo, haz que vuelva a pasar el problema y luego envía un informe al servidor.';

  @override
  String get kostvReportSent => 'Informe enviado al servidor';

  @override
  String kostvReportSentAs(String fileName) {
    return 'Informe enviado al servidor: $fileName';
  }

  @override
  String kostvReportSendFailed(String detail) {
    return 'No se ha podido enviar el informe: $detail';
  }

  @override
  String get kostvLogsCopied => 'Registros copiados al portapapeles';

  @override
  String get kostvLogEntryCopied => 'Entrada copiada al portapapeles';

  @override
  String get kostvLogsCleared => 'Registros borrados';

  @override
  String kostvFetchingList(String title) {
    return 'Descargando «$title»';
  }

  @override
  String get kostvServerReturnedNoItems => 'El servidor no ha devuelto nada.';

  @override
  String get kostvDeleteCustomRow => 'Eliminar la fila personalizada';

  @override
  String kostvDeleteCustomRowConfirm(String name) {
    return '¿Seguro que quieres eliminar «$name»?';
  }

  @override
  String get kostvCustomRowTypeList => 'Lista';

  @override
  String get kostvCustomRowTypeListFromUser => 'Lista por ID de usuario';

  @override
  String get kostvCustomRowTypeListFromUrl => 'Lista desde una URL';

  @override
  String get kostvCustomRowTypeDiary => 'Diario';

  @override
  String get kostvCustomRowTypeFilms => 'Todas las películas';

  @override
  String get kostvCustomRowTypeAwards => 'Premios y eventos';

  @override
  String get kostvCustomRowTypeMovieCollection => 'Colección de películas';

  @override
  String get kostvCustomRowTypeTmdbList => 'Lista de TMDB (por ID o URL)';

  @override
  String get kostvCustomRowTypeTmdbCollection =>
      'Colección de TMDB (por ID o URL)';

  @override
  String get kostvCustomRowTypeCustomList => 'Lista personalizada';

  @override
  String kostvCustomRowSourceAndType(String source, String type) {
    return '$type de $source';
  }

  @override
  String get kostvAddCustomRow => 'Añadir una fila personalizada a Inicio';

  @override
  String get kostvAddCustomRowSubtitle =>
      'Crea una fila con una lista de TMDB, Letterboxd o MDBList.';

  @override
  String get kostvSavedCustomRows => 'Filas personalizadas guardadas';

  @override
  String get kostvCustomRow => 'Fila personalizada';

  @override
  String kostvCustomRowSourceType(String source, String type) {
    return 'Origen: $source · Tipo: $type';
  }

  @override
  String get kostvDiscardChangesTitle => '¿Descartar los cambios?';

  @override
  String get kostvDiscardChangesMessage =>
      'Tienes cambios sin guardar. ¿Quieres salir sin guardarlos?';

  @override
  String get kostvCustomRowNoResults =>
      'La lista no ha devuelto ningún resultado.';

  @override
  String get kostvCustomRowCheckFailedTitle =>
      'No se ha podido comprobar la fila';

  @override
  String get kostvCustomRowCheckFailedMessage =>
      'No se han podido traer los títulos de esta fila personalizada.';

  @override
  String kostvErrorDetails(String detail) {
    return 'Detalles del error: $detail';
  }

  @override
  String get kostvEditCustomRow => 'Editar la fila personalizada';

  @override
  String get kostvNewCustomRow => 'Nueva fila personalizada';

  @override
  String get kostvLetterboxdUsername => 'Usuario de Letterboxd';

  @override
  String get kostvLetterboxdNeedsTmdbKey =>
      'Aviso: hace falta una clave de la API de TMDB en los ajustes para encontrar los títulos de las listas de Letterboxd.';

  @override
  String get kostvTmdbCollectionIdOrUrl => 'ID o URL de la colección de TMDB';

  @override
  String get kostvTmdbListIdOrUrl => 'ID o URL de la lista de TMDB';

  @override
  String get kostvTmdbCollectionHint =>
      '12345 o https://www.themoviedb.org/collection/12345';

  @override
  String get kostvTmdbListHint =>
      '12345 o https://www.themoviedb.org/list/12345';

  @override
  String get kostvTmdbNeedsKey =>
      'Aviso: hace falta una clave de la API de TMDB en los ajustes para traer listas de TMDB.';

  @override
  String get kostvMdblistUrl => 'URL de MDBList';

  @override
  String get kostvMdblistUrlHint =>
      'p. ej., https://mdblist.com/lists/usuario/nombre-de-la-lista';

  @override
  String get kostvMdblistUsername => 'Usuario de MDBList';

  @override
  String get kostvMdblistListName => 'Nombre de la lista (como sale en su URL)';

  @override
  String get kostvMdblistListNameHint => 'nombre-de-la-lista';

  @override
  String get kostvMdblistNeedsKey =>
      'Aviso: para traer listas de MDBList hace falta una clave de la API de MDBList en los ajustes (o que quien administra el servidor la configure para todos).';

  @override
  String get kostvSortAToZ => 'De la A a la Z';

  @override
  String get kostvSortMostPopularFirst => 'Más populares primero';

  @override
  String get kostvSortLeastPopularFirst => 'Menos populares primero';

  @override
  String get kostvSortHighestRatedFirst => 'Mejor valoradas primero';

  @override
  String get kostvSortLowestRatedFirst => 'Peor valoradas primero';

  @override
  String get kostvShowUserRatings => 'Mostrar las valoraciones del usuario';

  @override
  String get kostvCustomRowName => 'Nombre de la fila en Inicio';

  @override
  String get kostvCustomRowNameHint => 'Escribe un nombre para la fila…';

  @override
  String get kostvRewatchSortDescription =>
      'Elige cómo ordenar lo que ya has visto.';

  @override
  String get kostvRewatchIncludeMovies => 'Incluir películas';

  @override
  String get kostvRewatchIncludeMoviesSubtitle =>
      'Muestra en «Volver a ver» las películas que ya has visto.';

  @override
  String get kostvRewatchIncludeShows => 'Incluir series';

  @override
  String get kostvRewatchIncludeShowsSubtitle =>
      'Muestra en «Volver a ver» las series que ya has visto.';

  @override
  String get kostvRewatchIncludeCollections => 'Incluir colecciones';

  @override
  String get kostvRewatchIncludeCollectionsSubtitle =>
      'Muestra en «Volver a ver» las colecciones que ya has visto.';

  @override
  String kostvStudiosLoadFailed(String detail) {
    return 'No se han podido cargar los estudios: $detail';
  }

  @override
  String get kostvNoStudiosFound => 'No hay estudios en tus bibliotecas.';

  @override
  String kostvStudiosSelectedCount(int selected, int total, int visible) {
    return '$selected de $total elegidos ($visible a la vista)';
  }

  @override
  String get kostvAudioRow => 'Fila de audio';

  @override
  String get kostvCollectionsRow => 'Fila de colecciones';

  @override
  String kostvCollectionsRowFrom(String server) {
    return 'Fila de colecciones de $server';
  }

  @override
  String get kostvGenresRow => 'Fila de géneros';

  @override
  String get kostvPlaylistsRow => 'Fila de listas de reproducción';

  @override
  String get kostvFavoriteMovies => 'Películas favoritas';

  @override
  String get kostvFavoriteSeries => 'Series favoritas';

  @override
  String get kostvFavoriteEpisodes => 'Episodios favoritos';

  @override
  String get kostvFavoritePeople => 'Personas favoritas';

  @override
  String get kostvFavoriteArtists => 'Artistas favoritos';

  @override
  String get kostvFavoriteMusicVideos => 'Vídeos musicales favoritos';

  @override
  String get kostvFavoriteAlbums => 'Álbumes favoritos';

  @override
  String get kostvFavoriteSongs => 'Canciones favoritas';

  @override
  String get kostvFavoriteCollections => 'Colecciones favoritas';

  @override
  String get kostvCoreNotDownloaded => 'Este núcleo aún no está descargado.';

  @override
  String get kostvCoreSettingsUnreadable =>
      'Los ajustes de este núcleo no se pueden leer en este dispositivo. Aun así, puedes restablecerlos abajo.';

  @override
  String get kostvCoreSettingsReadFailed =>
      'No se han podido leer los ajustes de este núcleo.';

  @override
  String get kostvCoreSettingsSaveFailed =>
      'No se han podido guardar estos ajustes.';

  @override
  String kostvCoreSettingsTitle(String system) {
    return 'Ajustes de $system';
  }

  @override
  String get kostvCoreSettingsWarning =>
      'Son los ajustes propios del núcleo del emulador. Algunas combinaciones pueden impedir que un juego arranque o cerrar la app mientras juegas. Si algo falla, usa «Restablecer valores predeterminados», abajo.';

  @override
  String get kostvSegmentIntro => 'intro';

  @override
  String get kostvSegmentOutro => 'créditos';

  @override
  String get kostvSegmentPreview => 'avance';

  @override
  String get kostvSegmentRecap => 'resumen';

  @override
  String get kostvSegmentCommercial => 'anuncios';

  @override
  String get kostvSegmentUnknown => 'segmento';

  @override
  String get kostvDownloadQualityHigh => 'Alta (1080p)';

  @override
  String get kostvDownloadQualityLow => 'Baja (480p)';

  @override
  String get kostvDownloadQualityMobile => 'Móvil (360p)';

  @override
  String get kostvSizeVaries => 'Variable';

  @override
  String kostvSizePerHourGb(double size) {
    final intl.NumberFormat sizeNumberFormat =
        intl.NumberFormat.decimalPatternDigits(
          locale: localeName,
          decimalDigits: 1,
        );
    final String sizeString = sizeNumberFormat.format(size);

    return '~$sizeString GB/h';
  }

  @override
  String kostvSizePerHourMb(int size) {
    return '~$size MB/h';
  }

  @override
  String get kostvLoadingStream => 'Cargando el vídeo…';

  @override
  String get kostvStoppingPreviousPlayback => 'Parando el vídeo anterior…';

  @override
  String get kostvRestoringPosition => 'Volviendo a donde lo dejaste…';

  @override
  String get kostvRequestAsk => 'Solicitar';

  @override
  String get kostvRequestAskAndNotify => 'Solicitar y avisarme';

  @override
  String get kostvRequestNotifyMe => 'Avísame cuando esté';

  @override
  String get kostvRequestAskAll => 'Solicitar todo lo que falta';

  @override
  String kostvRequestAskSeason(int season) {
    return 'Solicitar la T$season';
  }

  @override
  String get kostvRequestMeToo => 'Yo también';

  @override
  String get kostvRequestWithdraw => 'Retirar petición';

  @override
  String get kostvRequestOpenInLibrary => 'Ver en la biblioteca';

  @override
  String get kostvRequestFast => 'Rápida';

  @override
  String get kostvRequestDownloadsWhenReady =>
      'Si la solicitas, se descargará sola en cuanto haya una buena';

  @override
  String get kostvRequestNeedsApproval =>
      'El administrador tiene que aceptarla';

  @override
  String get kostvRequestUnavailable => 'No se puede conseguir';

  @override
  String kostvRequestAtLimitPending(int pending) {
    String _temp0 = intl.Intl.pluralLogic(
      pending,
      locale: localeName,
      other: 'Tienes $pending peticiones esperando respuesta',
      one: 'Tienes 1 petición esperando respuesta',
    );
    return '$_temp0: podrás pedir más cuando te contesten';
  }

  @override
  String get kostvRequestAtLimitDaily =>
      'Has hecho todas las peticiones de hoy: mañana podrás pedir más';

  @override
  String get kostvRequestAtLimit => 'Ahora mismo no puedes solicitar nada más';

  @override
  String get kostvRequestPending => 'Pendiente de aprobación';

  @override
  String get kostvRequestUpdatesOnItsOwn =>
      'Esta ficha cambia sola en cuanto conteste';

  @override
  String get kostvRequestAccepted => 'Aceptada: empieza en seguida';

  @override
  String get kostvRequestLookingForEpisodes => 'Buscando los episodios';

  @override
  String get kostvRequestWaitingVersion => 'Esperando una versión buena';

  @override
  String get kostvRequestQueued => 'En cola';

  @override
  String get kostvRequestPreparing => 'Preparando';

  @override
  String get kostvRequestWaitingFile => 'Esperando a que el archivo esté listo';

  @override
  String kostvRequestDownloadingPercent(int percent) {
    return 'Descargando $percent %';
  }

  @override
  String get kostvRequestDownloading => 'Descargando';

  @override
  String get kostvRequestVerifying => 'Comprobando el vídeo';

  @override
  String get kostvRequestMoving => 'Colocándola en la biblioteca';

  @override
  String get kostvRequestAttention =>
      'En revisión: el administrador tiene que elegir otra versión';

  @override
  String get kostvRequestPaused => 'En pausa';

  @override
  String kostvHoursMinutes(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String get kostvRequestRejected => 'No aceptada';

  @override
  String get kostvRequestRejectedQuality =>
      'No aceptada: aún no hay una versión buena';

  @override
  String get kostvRequestRejectedLater => 'No aceptada: mejor más adelante';

  @override
  String get kostvRequestArrived => '¡Ya está aquí!';

  @override
  String get kostvRequestArrivingSoon =>
      'Recién llegada: aparecerá en la biblioteca en unos minutos';

  @override
  String get kostvRequestLoadFailed => 'No se ha podido abrir esta ficha';

  @override
  String get kostvRequestSeasonComplete => 'Completa';

  @override
  String get kostvRequestSeasonUpcoming => 'Aún no se ha estrenado';

  @override
  String get kostvRequestSeasonOnItsWay => 'De camino';

  @override
  String get kostvRequestOutcomeCreated =>
      'Petición enviada: el administrador tiene que aceptarla';

  @override
  String get kostvRequestOutcomeStarted => '¡Solicitada! Ya se está preparando';

  @override
  String get kostvRequestOutcomeJoined =>
      'Alguien ya la había solicitado: te hemos apuntado';

  @override
  String get kostvRequestOutcomeWatching =>
      'Ya se estaba descargando: te apuntamos para cuando llegue';

  @override
  String get kostvRequestOutcomeIncluded =>
      'Ya estaba solicitado todo lo que falta, también esta temporada';

  @override
  String get kostvRequestOutcomeAlready => 'Ya lo habías solicitado';

  @override
  String get kostvRequestOutcomeHave => 'Ya está en la biblioteca';

  @override
  String get kostvRequestOutcomeBusy => 'Ya se está descargando';

  @override
  String get kostvRequestWithdrawn => 'Petición retirada';

  @override
  String get kostvRequestFailed =>
      'No se ha podido enviar la petición. Inténtalo otra vez.';

  @override
  String get kostvRequestTooFast =>
      'Demasiadas seguidas: espera un momento y vuelve a intentarlo';

  @override
  String kostvRequestWaitingSince(int minutes) {
    return 'desde hace $minutes min';
  }

  @override
  String get kostvRequestUnderReview => 'En revisión';

  @override
  String kostvRequestWithdrawQuestion(String title) {
    return '¿Retiras la petición de $title?';
  }

  @override
  String get kostvRequestNotHomeYet => 'Todavía no está en casa';

  @override
  String get kostvStatQuality => 'Calidad';

  @override
  String get kostvStatLanguage => 'Idioma';

  @override
  String get kostvStatSize => 'Tamaño';

  @override
  String get kostvStatDownload => 'Descarga';

  @override
  String get kostvStatRelease => 'Estreno';

  @override
  String get kostvStatVersion => 'Versión';

  @override
  String get kostvStatAvailability => 'Disponibilidad';

  @override
  String get kostvStatProgress => 'Progreso';

  @override
  String get kostvStatSpeed => 'Velocidad';

  @override
  String get kostvStatTimeLeft => 'Quedan';

  @override
  String get kostvStatStatus => 'Estado';

  @override
  String get kostvStatRequestedBy => 'Solicitada por';

  @override
  String get kostvStatEpisodes => 'Episodios';

  @override
  String get kostvStatAtHome => 'En casa';

  @override
  String get kostvStatMissing => 'Faltan';

  @override
  String get kostvValueNormal => 'Normal';

  @override
  String get kostvValueNoneYet => 'Aún no hay';

  @override
  String get kostvValueNoGoodOneYet => 'Aún no hay buena';

  @override
  String get kostvValueChecking => 'Mirando…';

  @override
  String get kostvValueYou => 'Tú';

  @override
  String kostvValueYouAnd(String names) {
    return 'Tú y $names';
  }

  @override
  String kostvValueOf(int done, int total) {
    return '$done de $total';
  }

  @override
  String get kostvValueUnderAMinute => '< 1 min';

  @override
  String get kostvStepAsk => 'Solicitud';

  @override
  String get kostvStepAsked => 'Solicitada';

  @override
  String get kostvStepApproval => 'Aceptación';

  @override
  String get kostvStepApproved => 'Aceptada';

  @override
  String get kostvStepRejected => 'No aceptada';

  @override
  String get kostvStepDownload => 'Descarga';

  @override
  String get kostvStepHome => 'En casa';

  @override
  String kostvSeasonEpisodeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodios',
      one: '1 episodio',
    );
    return '$_temp0';
  }

  @override
  String kostvSeasonAtHome(int have, int aired) {
    return '$have de $aired en casa';
  }

  @override
  String kostvPercent(int percent) {
    return '$percent %';
  }

  @override
  String get kostvValuePending => 'Pendiente';

  @override
  String get kostvStatWanted => 'Se busca';

  @override
  String get kostvRequestLimitReached => 'Has llegado al límite de peticiones';

  @override
  String get kostvTrayTitle => 'Peticiones';

  @override
  String get kostvTrayOpen => 'Bandeja de peticiones';

  @override
  String get kostvTrayNews => 'Novedades';

  @override
  String get kostvTrayActive => 'En marcha';

  @override
  String get kostvTrayFinished => 'Terminadas';

  @override
  String get kostvTrayEmpty => 'Aún no has solicitado nada';

  @override
  String get kostvTrayEmptyHint =>
      'Lo que solicites desde Descubrir aparecerá aquí.';

  @override
  String get kostvTrayGoDiscover => 'Ir a Descubrir';

  @override
  String get kostvTrayLoadFailed => 'No se han podido cargar tus peticiones';

  @override
  String kostvTrayQuotaDaily(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Te quedan $count hoy',
      one: 'Te queda 1 hoy',
    );
    return '$_temp0';
  }

  @override
  String kostvTrayQuotaPending(int pending, int limit) {
    return '$pending de $limit esperando respuesta';
  }

  @override
  String get kostvTrayWithdraw => 'Retirar';

  @override
  String kostvTrayEpisodes(int done, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total episodios',
      one: '1 episodio',
    );
    return '$done de $_temp0';
  }

  @override
  String kostvTrayTimeLeft(String time) {
    return 'quedan $time';
  }

  @override
  String get kostvDiscoverKindMovie => 'Película';

  @override
  String get kostvDiscoverKindSeries => 'Serie';

  @override
  String kostvDiscoverRank(int rank) {
    return 'N.º $rank';
  }

  @override
  String get kostvSearchRequestable => 'Para solicitar';

  @override
  String get kostvSearchNotHome => 'No está en casa, pero puedes solicitarlo';

  @override
  String get kostvSearchLookingOutside => 'Buscando lo que puedes solicitar…';

  @override
  String get kostvSearchMore => 'Ver más';

  @override
  String get kostvLauncherMode => 'Modo launcher';

  @override
  String get kostvLauncherModeSubtitle =>
      'Para una tele en la que kOS TV es lo primero que se ve';

  @override
  String get kostvLauncherModeIntro =>
      'Para una tele en la que kOS TV es la pantalla de inicio y no una aplicación más. Estas opciones se guardan solo en esta tele.';

  @override
  String get kostvIntroSetting => 'Animación al abrir';

  @override
  String get kostvIntroSettingSubtitle =>
      'El vídeo de kOS TV al abrir la aplicación';

  @override
  String get kostvShowAppsButtonSubtitle =>
      'Un botón «Aplicaciones» en el menú con todas las de la tele';

  @override
  String get kostvChooseRowApps => 'Elegir las aplicaciones de la fila';

  @override
  String get kostvChooseRowAppsSubtitle =>
      'En «Todas las aplicaciones», mantén pulsado OK sobre una para añadirla a Inicio o quitarla';

  @override
  String get kostvAgeBlocked => 'No disponible para tu perfil';

  @override
  String get kostvAgeBlockedNote =>
      'Por su edad recomendada, este título no está disponible con tu perfil.';

  @override
  String get kostvGhostNotAtHome => 'No está en casa';

  @override
  String get kostvGhostAskedByOther => 'Ya lo ha pedido otra persona';

  @override
  String get kostvGhostPending => 'Lo has solicitado: falta que lo acepten';

  @override
  String get kostvGhostAccepted => 'Solicitado y aceptado: llegará pronto';

  @override
  String get kostvGhostDownloadingNote =>
      'Se está descargando: llegará en seguida';

  @override
  String get kostvGhostNotOnYet => 'Todavía no se ha emitido';

  @override
  String get kostvGhostRequested => 'Solicitado';

  @override
  String kostvGhostPremieres(String date) {
    return 'Se estrena el $date';
  }

  @override
  String get kostvGhostPremieresToday => 'Se estrena hoy';

  @override
  String get kostvGhostPremieresTomorrow => 'Se estrena mañana';

  @override
  String get kostvGhostComingSoon => 'Próximamente';

  @override
  String kostvGhostAired(String date) {
    return 'Se emitió el $date';
  }

  @override
  String kostvGhostAskMissing(int count) {
    return 'Solicitar los $count que faltan';
  }

  @override
  String kostvGhostSeasonMissing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Faltan $count episodios de esta temporada',
      one: 'Falta 1 episodio de esta temporada',
    );
    return '$_temp0';
  }

  @override
  String get kostvGhostSeasonNotAtHome => 'Esta temporada no está en casa';

  @override
  String get kostvGhostAskSeason => 'Solicitar la temporada';

  @override
  String get kostvGhostSeasonRequested => 'Temporada solicitada';

  @override
  String get kostvGhostAskEpisode => 'Solicitar este episodio';

  @override
  String get kostvGhostOutcomeStarted => '¡Solicitado! Ya se está preparando';

  @override
  String get kostvGhostOutcomeJoined =>
      'Alguien ya lo había solicitado: te hemos apuntado';

  @override
  String kostvGapOne(int number) {
    return 'El episodio $number no está en casa';
  }

  @override
  String kostvGapMany(int first, int last) {
    return 'Los episodios del $first al $last no están en casa';
  }

  @override
  String kostvGapAsk(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Solicitarlos',
      one: 'Solicitarlo',
    );
    return '$_temp0';
  }

  @override
  String kostvGapRequested(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Solicitados',
      one: 'Solicitado',
    );
    return '$_temp0';
  }

  @override
  String kostvGapWatch(int number) {
    return 'Ver el $number';
  }

  @override
  String kostvGapWatchOther(int season, int episode) {
    return 'Ver S$season:E$episode';
  }
}
