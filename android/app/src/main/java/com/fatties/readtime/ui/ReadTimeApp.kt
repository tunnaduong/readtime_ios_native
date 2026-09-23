package com.fatties.readtime.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.outlined.TrackChanges
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavGraphBuilder
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.fatties.readtime.R
import com.fatties.readtime.data.AdManager
import com.fatties.readtime.data.AppearanceController
import com.fatties.readtime.data.PurchaseManager
import com.fatties.readtime.data.ReadingStore
import com.fatties.readtime.ui.screens.AboutScreen
import com.fatties.readtime.ui.screens.AddBookScreen
import com.fatties.readtime.ui.screens.CreateGoalScreen
import com.fatties.readtime.ui.screens.GoalsScreen
import com.fatties.readtime.ui.screens.HomeScreen
import com.fatties.readtime.ui.screens.ImportExportScreen
import com.fatties.readtime.ui.screens.JournalScreen
import com.fatties.readtime.ui.screens.LibraryScreen
import com.fatties.readtime.ui.screens.OnboardingScreen
import com.fatties.readtime.ui.screens.PaywallScreen
import com.fatties.readtime.ui.screens.ReadingSessionScreen
import com.fatties.readtime.ui.screens.SettingsScreen
import com.fatties.readtime.ui.screens.StatsScreen
import com.fatties.readtime.ui.theme.ReadTimeTheme

object Routes {
    const val HOME = "home"
    const val GOALS = "goals"
    const val LIBRARY = "library"
    const val STATS = "stats"
    const val JOURNAL = "journal"
    const val SETTINGS = "settings"
    const val ABOUT = "about"
    const val IMPORT_EXPORT = "importExport"
    const val PAYWALL = "paywall"
    const val SESSION = "session/{bookId}"
    const val ADD_BOOK = "addBook?bookId={bookId}"
    const val CREATE_GOAL = "createGoal/{kind}"

    fun session(bookID: String) = "session/$bookID"
    fun addBook(bookID: String? = null) = if (bookID == null) "addBook" else "addBook?bookId=$bookID"
    fun createGoal(kind: String) = "createGoal/$kind"
}

private data class Tab(val route: String, val labelRes: Int, val icon: ImageVector)

private val TABS = listOf(
    Tab(Routes.HOME, R.string.s_home, Icons.Default.Home),
    Tab(Routes.GOALS, R.string.s_goals, Icons.Outlined.TrackChanges),
    Tab(Routes.LIBRARY, R.string.s_library, Icons.AutoMirrored.Filled.MenuBook),
    Tab(Routes.STATS, R.string.s_stats, Icons.Default.BarChart),
)

@Composable
fun ReadTimeApp(store: ReadingStore, purchases: PurchaseManager, appearance: AppearanceController) {
    val state by store.state.collectAsStateWithLifecycle()
    val navController = rememberNavController()

    if (state.needsOnboarding) {
        Box(
            Modifier
                .fillMaxSize()
                .safeDrawingPadding()
                .imePadding()
        ) {
            OnboardingScreen(store = store)
        }
        return
    }

    // Consent-free start once onboarding is done, matching the iOS app's timing.
    val context = LocalContext.current
    LaunchedEffect(Unit) { AdManager.start(context) }

    val backStack by navController.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route
    val showsTabs = currentRoute in TABS.map { it.route }

    Scaffold(
        containerColor = ReadTimeTheme.colors.background,
        bottomBar = {
            if (showsTabs) {
                NavigationBar(containerColor = ReadTimeTheme.colors.card) {
                    TABS.forEach { tab ->
                        NavigationBarItem(
                            selected = currentRoute == tab.route,
                            onClick = {
                                if (currentRoute != tab.route) {
                                    navController.navigate(tab.route) {
                                        popUpTo(Routes.HOME) { saveState = true }
                                        launchSingleTop = true
                                        restoreState = true
                                    }
                                }
                            },
                            icon = { Icon(tab.icon, contentDescription = null) },
                            label = { Text(stringResource(tab.labelRes)) },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = ReadTimeTheme.colors.purple,
                                selectedTextColor = ReadTimeTheme.colors.purple,
                                indicatorColor = ReadTimeTheme.colors.purple.copy(alpha = 0.12f),
                            ),
                        )
                    }
                }
            }
        },
    ) { padding ->
        Box(
            Modifier
                .fillMaxSize()
                .padding(padding)
                // Lifts whatever is on screen above the keyboard, since the app draws edge to edge.
                .imePadding()
        ) {
            NavHost(navController = navController, startDestination = Routes.HOME) {
                appGraph(navController, store, purchases, appearance)
            }
        }
    }
}

private fun NavGraphBuilder.appGraph(
    navController: NavHostController,
    store: ReadingStore,
    purchases: PurchaseManager,
    appearance: AppearanceController,
) {
    composable(Routes.HOME) { HomeScreen(store, navController) }
    composable(Routes.GOALS) { GoalsScreen(store, navController) }
    composable(Routes.LIBRARY) { LibraryScreen(store, navController) }
    composable(Routes.STATS) { StatsScreen(store, navController) }
    composable(Routes.JOURNAL) { JournalScreen(store, navController) }
    composable(Routes.SETTINGS) { SettingsScreen(store, purchases, appearance, navController) }
    composable(Routes.PAYWALL) { PaywallScreen(purchases) { navController.popBackStack() } }
    composable(Routes.ABOUT) { AboutScreen(navController) }
    composable(Routes.IMPORT_EXPORT) { ImportExportScreen(store, navController) }
    composable(Routes.SESSION) { entry ->
        ReadingSessionScreen(store, navController, entry.arguments?.getString("bookId").orEmpty())
    }
    composable(Routes.ADD_BOOK) { entry ->
        AddBookScreen(store, { navController.popBackStack() }, entry.arguments?.getString("bookId"))
    }
    composable(Routes.CREATE_GOAL) { entry ->
        CreateGoalScreen(store, navController, entry.arguments?.getString("kind") ?: "daily")
    }
}
