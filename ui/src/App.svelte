<script lang="ts">
	import HygieneAudio from '@components/HygieneAudio.svelte'
	import VisibilityProvider from '@providers/VisibilityProvider.svelte'
	import {
		CURRENTFURNITURE,
		FURNITURES,
		browserMode,
		resName,
	} from '@store/stores'
	import DebugBrowser from '@providers/DebugBrowser.svelte'
	import AlwaysListener from '@providers/AlwaysListener.svelte'
	import Menu from '@components/Furnishing.svelte'


	import ModelStore from '@store/ModelStore'

	$resName = 'forge-housing' // Change this to your resource name (case sensitive)

	const { show } = ModelStore

</script>

<VisibilityProvider>
	{#if $FURNITURES}
		<Menu />

	{/if}
</VisibilityProvider>

<AlwaysListener /><HygieneAudio />
{#if $browserMode}
	<DebugBrowser />
	<body class=" bg-neutral-700"></body>
{/if}
