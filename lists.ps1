function Get-LeftBackups{
    param (
        [string] $listName
    )
    $camlNotTerminado = "@
    <View>
        <Query>
            <Where>
                <Eq>
                    <FieldRef Name='Backup' />
                    <Value Type='Text'>Terminado</Value>
                </Eq>
            </Where>
        </Query>
    </View>"
    return Get-PnPListItem -List $listName -Query $camlNotTerminado
}

